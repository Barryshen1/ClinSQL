WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND admittime <= dischtime  -- Ensure valid LOS
),
comorbidities AS (
  SELECT
    hadm_id,
    -- CKD flag (ICD-9: 585.x, ICD-10: N18.x)
    MAX(CASE
          WHEN (icd_version = 9 AND icd_code LIKE '585%') OR 
               (icd_version = 10 AND icd_code LIKE 'N18%') 
          THEN 1 ELSE 0 END) AS ckd_flag,
    -- Diabetes flag (ICD-9: 250.x, ICD-10: E10-E14)
    MAX(CASE
          WHEN (icd_version = 9 AND icd_code LIKE '250%') OR 
               (icd_version = 10 AND icd_code LIKE 'E1%') 
          THEN 1 ELSE 0 END) AS diabetes_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
combined_data AS (
  SELECT
    c.*,
    COALESCE(cm.ckd_flag, 0) AS ckd_flag,
    COALESCE(cm.diabetes_flag, 0) AS diabetes_flag
  FROM cohort c
  LEFT JOIN comorbidities cm
    ON c.hadm_id = cm.hadm_id
  WHERE
    c.age_at_admit BETWEEN 68 AND 78  -- Age filter
),
los_groups AS (
  SELECT *,
    CASE WHEN los_days < 8 THEN '<8' ELSE '>=8' END AS los_group
  FROM combined_data
)
SELECT
  los_group,
  COUNT(*) AS admissions,
  ROUND(100 * AVG(CAST(hospital_expire_flag AS FLOAT64)), 2) AS in_hospital_mortality_percent,
  ROUND(100 * AVG(CAST(ckd_flag AS FLOAT64)), 2) AS ckd_prevalence_percent,
  ROUND(100 * AVG(CAST(diabetes_flag AS FLOAT64)), 2) AS diabetes_prevalence_percent
FROM los_groups
GROUP BY los_group
ORDER BY los_group;