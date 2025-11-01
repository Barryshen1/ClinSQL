WITH heart_failure_patients AS (
  -- Identify patients with heart failure diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        -- Heart failure ICD codes (ICD-9 and ICD-10)
        (icd_version = 9 AND icd_code LIKE '428.%')
        OR (icd_version = 9 AND icd_code LIKE '402.%1')
        OR (icd_version = 9 AND icd_code LIKE '404.%1')
        OR (icd_version = 9 AND icd_code LIKE '404.%3')
        OR (icd_version = 10 AND icd_code LIKE 'I50.%')
    )
),

ckd_patients AS (
  -- Identify patients with CKD diagnosis
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- CKD ICD codes (ICD-9 and ICD-10)
    (icd_version = 9 AND icd_code LIKE '585.%')
    OR (icd_version = 9 AND icd_code = '586')
    OR (icd_version = 9 AND icd_code LIKE '588.%')
    OR (icd_version = 10 AND icd_code LIKE 'N18.%')
    OR (icd_version = 10 AND icd_code = 'N19')
),

diabetes_patients AS (
  -- Identify patients with diabetes diagnosis
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- Diabetes ICD codes (ICD-9 and ICD-10)
    (icd_version = 9 AND icd_code LIKE '250.%')
    OR (icd_version = 10 AND icd_code LIKE 'E11.%')
    OR (icd_version = 10 AND icd_code LIKE 'E13.%')
),

final_cohort AS (
  -- Combine all information
  SELECT
    hf.subject_id,
    hf.hadm_id,
    hf.los_days,
    hf.hospital_expire_flag,
    CASE WHEN c.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_ckd,
    CASE WHEN d.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_diabetes,
    CASE WHEN hf.los_days < 8 THEN '<8 days' ELSE '>=8 days' END AS los_stratification
  FROM
    heart_failure_patients hf
  LEFT JOIN
    ckd_patients c
  ON
    hf.subject_id = c.subject_id AND hf.hadm_id = c.hadm_id
  LEFT JOIN
    diabetes_patients d
  ON
    hf.subject_id = d.subject_id AND hf.hadm_id = d.hadm_id
)

-- Final aggregation
SELECT
  los_stratification,
  COUNT(*) AS total_patients,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS in_hospital_mortality_pct,
  ROUND(100 * SUM(has_ckd) / COUNT(*), 2) AS ckd_prevalence_pct,
  ROUND(100 * SUM(has_diabetes) / COUNT(*), 2) AS diabetes_prevalence_pct
FROM
  final_cohort
GROUP BY
  los_stratification
ORDER BY
  los_stratification;