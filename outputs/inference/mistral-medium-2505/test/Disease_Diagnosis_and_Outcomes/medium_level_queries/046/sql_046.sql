WITH
-- Define heart failure ICD codes (I50.*)
heart_failure_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'I50.%'
),

-- Get all male patients aged 72-82 with heart failure
hf_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 3 THEN '≤3 days'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 6 THEN '4-6 days'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 7 AND 10 THEN '7-10 days'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) > 10 THEN '>10 days'
    END AS los_category,
    -- Check if patient had ICU stay
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS admission_type
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 72 AND 82
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code IN (SELECT icd_code FROM heart_failure_codes)
    )
    AND a.dischtime IS NOT NULL
),

-- Count comorbidities (excluding heart failure)
comorbidity_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code NOT IN (SELECT icd_code FROM heart_failure_codes)
  GROUP BY hadm_id
)

-- Final aggregation
SELECT
  admission_type,
  los_category,
  COUNT(*) AS admission_count,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_mortality,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 4) AS mortality_rate,
  APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS median_los,
  AVG(comorbidity_count) AS avg_comorbidity_count
FROM hf_patients
LEFT JOIN comorbidity_counts USING (hadm_id)
GROUP BY admission_type, los_category
ORDER BY admission_type, los_category;