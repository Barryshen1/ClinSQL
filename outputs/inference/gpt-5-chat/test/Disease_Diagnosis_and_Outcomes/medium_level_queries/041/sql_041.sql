WITH sepsis_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE (
      -- ICD-9 codes for sepsis/severe sepsis
      (d.icd_version = 9 AND (
        d.icd_code LIKE '038%' OR
        d.icd_code IN ('99591','99592')
      ))
      -- ICD-10 codes for sepsis
      OR (d.icd_version = 10 AND (
        d.icd_code LIKE 'A40%' OR
        d.icd_code LIKE 'A41%' OR
        d.icd_code = 'R6520' -- severe sepsis without septic shock
      ))
    )
),
shock_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE (
      -- ICD-9 septic shock
      (d.icd_version = 9 AND d.icd_code = '78552')
      -- ICD-10 septic shock
      OR (d.icd_version = 10 AND d.icd_code = 'R6521')
      -- Also search text to be safe
      OR LOWER(dd.long_title) LIKE '%septic shock%'
    )
),
sepsis_no_shock AS (
  SELECT s.hadm_id
  FROM sepsis_hadm s
  LEFT JOIN shock_hadm sh ON s.hadm_id = sh.hadm_id
  WHERE sh.hadm_id IS NULL
),
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) <= 7 THEN '<=7'
         ELSE '>7' END AS los_group,
    CASE WHEN a.hospital_expire_flag = 1
         THEN DATETIME_DIFF(a.deathtime, a.admittime, DAY)
    END AS days_to_death
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN sepsis_no_shock sns
    ON a.hadm_id = sns.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
),
mortality_stats AS (
  SELECT
    los_group,
    COUNT(*) AS n_admissions,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
    100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_pct
  FROM cohort
  GROUP BY los_group
),
diffs AS (
  SELECT
    m1.mortality_pct AS mort_le_7,
    m2.mortality_pct AS mort_gt_7,
    (m2.mortality_pct - m1.mortality_pct) AS abs_diff_pct_points,
    (m2.mortality_pct - m1.mortality_pct) / m1.mortality_pct AS rel_diff
  FROM mortality_stats m1
  JOIN mortality_stats m2
    ON m1.los_group = '<=7' AND m2.los_group = '>7'
),
median_ttd AS (
  SELECT
    APPROX_QUANTILES(days_to_death, 2)[OFFSET(1)] AS median_days_to_death
  FROM cohort
  WHERE hospital_expire_flag = 1
    AND days_to_death IS NOT NULL
)
SELECT
  ms.los_group,
  ms.n_admissions,
  ms.deaths,
  ms.mortality_pct,
  d.abs_diff_pct_points,
  d.rel_diff,
  mtd.median_days_to_death
FROM mortality_stats ms
CROSS JOIN diffs d
CROSS JOIN median_ttd mtd
ORDER BY ms.los_group;