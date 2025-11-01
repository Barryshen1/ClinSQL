WITH base AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
),
sepsis_flags AS (
  SELECT
    b.hadm_id,
    MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%septic shock%' THEN 1 ELSE 0 END) AS has_shock,
    MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%sepsis%' OR LOWER(ddi.long_title) LIKE '%septicemia%' THEN 1 ELSE 0 END) AS has_sepsis
  FROM base AS b
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.hadm_id = b.hadm_id AND di.subject_id = b.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddi
    ON ddi.icd_code = di.icd_code AND ddi.icd_version = di.icd_version
  GROUP BY b.hadm_id
),
cohort AS (
  SELECT
    b.hadm_id,
    b.subject_id,
    b.admittime,
    b.dischtime,
    b.deathtime,
    CASE
      WHEN s.has_shock = 1 THEN 'Septic Shock'
      WHEN s.has_sepsis = 1 THEN 'Sepsis'
      ELSE NULL
    END AS sepsis_group
  FROM base AS b
  JOIN sepsis_flags AS s ON b.hadm_id = s.hadm_id
  WHERE CASE
          WHEN s.has_shock = 1 THEN 'Septic Shock'
          WHEN s.has_sepsis = 1 THEN 'Sepsis'
          ELSE NULL
        END IS NOT NULL
),
cohort_with_los AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    c.deathtime,
    c.sepsis_group,
    CASE
      WHEN TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) <= 7 THEN '<=7'
      ELSE '>7'
    END AS los_group
  FROM cohort c
),
med_input AS (
  SELECT
    cw.sepsis_group,
    cw.los_group,
    CASE WHEN cw.deathtime IS NOT NULL THEN TIMESTAMP_DIFF(cw.deathtime, cw.admittime, SECOND) / 86400.0
    END AS time_to_death_days
  FROM cohort_with_los cw
),
agg AS (
  SELECT
    sepsis_group,
    los_group,
    COUNT(*) AS N,
    SUM(CASE WHEN time_to_death_days IS NOT NULL THEN 1 ELSE 0 END) AS Deaths,
    APPROX_QUANTILES(time_to_death_days, 100)[OFFSET(50)] AS median_time_to_death_days
  FROM med_input
  GROUP BY sepsis_group, los_group
)
SELECT
  g.sepsis_group,
  MAX(CASE WHEN g.los_group = '<=7' THEN g.N END) AS N_LE7,
  MAX(CASE WHEN g.los_group = '<=7' THEN 100.0 * g.Deaths / NULLIF(g.N, 0) END) AS mort_rate_LE7_pct,
  MAX(CASE WHEN g.los_group = '<=7' THEN g.median_time_to_death_days END) AS median_time_to_death_LE7_days,
  MAX(CASE WHEN g.los_group = '>7' THEN g.N END) AS N_GT7,
  MAX(CASE WHEN g.los_group = '>7' THEN 100.0 * g.Deaths / NULLIF(g.N, 0) END) AS mort_rate_GT7_pct,
  MAX(CASE WHEN g.los_group = '>7' THEN g.median_time_to_death_days END) AS median_time_to_death_GT7_days,
  (
    MAX(CASE WHEN g.los_group = '<=7' THEN 100.0 * g.Deaths / NULLIF(g.N, 0) END)
    - MAX(CASE WHEN g.los_group = '>7' THEN 100.0 * g.Deaths / NULLIF(g.N, 0) END)
  ) AS abs_mort_diff_pct,
  CASE
    WHEN MAX(CASE WHEN g.los_group = '>7' THEN 100.0 * g.Deaths / NULLIF(g.N, 0) END) > 0
    THEN MAX(CASE WHEN g.los_group = '<=7' THEN 100.0 * g.Deaths / NULLIF(g.N, 0) END)
         / MAX(CASE WHEN g.los_group = '>7' THEN 100.0 * g.Deaths / NULLIF(g.N, 0) END)
    ELSE NULL
  END AS rel_mort_diff_ratio
FROM agg AS g
GROUP BY g.sepsis_group
ORDER BY g.sepsis_group;