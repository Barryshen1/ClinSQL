WITH diag_flags AS (
  -- Aggregate diagnosis-level information to hadm_id level: presence of sepsis, septic shock, CKD, diabetes
  SELECT
    di.hadm_id,
    MAX(CASE WHEN LOWER(COALESCE(d.long_title, '')) LIKE '%septic shock%' THEN 1 ELSE 0 END) AS has_septic_shock,
    MAX(CASE WHEN LOWER(COALESCE(d.long_title, '')) LIKE '%sepsis%' 
             AND LOWER(COALESCE(d.long_title, '')) NOT LIKE '%septic shock%' THEN 1 ELSE 0 END) AS has_sepsis,
    MAX(CASE WHEN LOWER(COALESCE(d.long_title, '')) LIKE '%chronic kidney%'
             OR LOWER(COALESCE(d.long_title, '')) LIKE '%chronic renal%'
             OR LOWER(COALESCE(d.long_title, '')) LIKE '%ckd%'
             OR LOWER(COALESCE(d.long_title, '')) LIKE '%end stage renal%'
             OR LOWER(COALESCE(d.long_title, '')) LIKE '%esrd%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN LOWER(COALESCE(d.long_title, '')) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  GROUP BY
    di.hadm_id
),

cohort AS (
  -- Admissions for male patients age 64-74 with sepsis (but without septic shock)
  SELECT
    a.hadm_id,
    a.subject_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    -- LOS in fractional days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    a.hospital_expire_flag,
    df.has_ckd,
    df.has_diabetes
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING(subject_id)
  JOIN
    diag_flags df
  USING(hadm_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND df.has_sepsis = 1
    AND df.has_septic_shock = 0
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- optional: ensure non-negative LOS
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 0
),

cohort_with_quartile AS (
  -- Assign LOS quartiles (Q1..Q4) using NTILE(4)
  SELECT
    c.*,
    NTILE(4) OVER (ORDER BY c.los_days) AS los_quartile
  FROM
    cohort c
)

SELECT
  CONCAT('Q', CAST(los_quartile AS STRING)) AS los_quartile,
  COUNT(*) AS n_admissions,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_pct,
  SUM(CASE WHEN has_ckd = 1 THEN 1 ELSE 0 END) AS n_ckd,
  ROUND(100.0 * SUM(CASE WHEN has_ckd = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS ckd_pct,
  SUM(CASE WHEN has_diabetes = 1 THEN 1 ELSE 0 END) AS n_diabetes,
  ROUND(100.0 * SUM(CASE WHEN has_diabetes = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS diabetes_pct,
  ROUND(MIN(los_days), 2) AS los_min_days,
  ROUND(MAX(los_days), 2) AS los_max_days,
  ROUND(AVG(los_days), 2) AS los_mean_days
FROM
  cohort_with_quartile
GROUP BY
  los_quartile
ORDER BY
  los_quartile;