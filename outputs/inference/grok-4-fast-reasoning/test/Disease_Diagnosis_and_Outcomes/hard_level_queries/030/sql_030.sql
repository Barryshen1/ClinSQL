WITH ugib_hadms AS (
  SELECT DISTINCT
    di.subject_id,
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%hemorrhage%'
    AND (
      LOWER(dd.long_title) LIKE '%upper%'
      OR LOWER(dd.long_title) LIKE '%gastr%'
      OR LOWER(dd.long_title) LIKE '%duoden%'
      OR LOWER(dd.long_title) LIKE '%esophag%'
      OR LOWER(dd.long_title) LIKE '%peptic%'
      OR LOWER(dd.long_title) LIKE '%stomach%'
    )
),
diag_counts AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(*) AS num_diagnoses
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY subject_id, hadm_id
),
major_comps AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(CAST(drg_severity AS INT64)) >= 3 AS major_comp_flag
  FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
  WHERE drg_type = 'APRDRG'
  GROUP BY subject_id, hadm_id
),
base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    COALESCE(dc.num_diagnoses, 0) AS num_diagnoses,
    COALESCE(mc.major_comp_flag, FALSE) AS major_comp_flag,
    COALESCE(dc.num_diagnoses, 0) + 20 * CAST(COALESCE(mc.major_comp_flag, FALSE) AS INT64) AS score,
    DATE(a.admittime) AS admit_date,
    IF(a.deathtime IS NOT NULL, DATE(a.deathtime), p.dod) AS death_date,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN diag_counts dc
    ON a.subject_id = dc.subject_id AND a.hadm_id = dc.hadm_id
  LEFT JOIN major_comps mc
    ON a.subject_id = mc.subject_id AND a.hadm_id = mc.hadm_id
  INNER JOIN ugib_hadms u
    ON a.subject_id = u.subject_id AND a.hadm_id = u.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND a.dischtime IS NOT NULL
),
cohort AS (
  SELECT
    *,
    CASE
      WHEN death_date IS NOT NULL AND death_date <= DATE_ADD(admit_date, INTERVAL 30 DAY)
      THEN 1
      ELSE 0
    END AS mortality_30d,
    NTILE(5) OVER (ORDER BY score ASC) AS quintile
  FROM base
),
stats AS (
  SELECT
    quintile,
    COUNT(*) AS n,
    ROUND(AVG(score), 2) AS mean_score,
    ROUND(AVG(CAST(mortality_30d AS FLOAT64)) * 100, 2) AS mortality_pct,
    ROUND(AVG(CAST(major_comp_flag AS FLOAT64)) * 100, 2) AS major_comp_pct
  FROM cohort
  GROUP BY quintile
),
median_los AS (
  SELECT
    quintile,
    PERCENTILE_CONT(los_days, 0.5) AS median_los_survivors
  FROM cohort
  WHERE mortality_30d = 0
  GROUP BY quintile
)
SELECT
  s.quintile,
  s.n,
  s.mean_score,
  s.mortality_pct,
  s.major_comp_pct,
  m.median_los_survivors
FROM stats s
LEFT JOIN median_los m
  ON s.quintile = m.quintile
ORDER BY s.quintile ASC;