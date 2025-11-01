WITH ugib_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE d.seq_num = 1  -- primary diagnosis
    AND d.icd_version = 10  -- ICD-10 codes only
    AND p.gender = 'F'
    AND (
      d.icd_code LIKE 'K25%' OR
      d.icd_code LIKE 'K26%' OR
      d.icd_code LIKE 'K27%' OR
      d.icd_code LIKE 'K28%' OR
      d.icd_code = 'K920' OR
      d.icd_code = 'K921' OR
      d.icd_code = 'K922' OR
      d.icd_code LIKE 'I85%'
    )
),
age_calculated AS (
  SELECT 
    hadm_id,
    admittime,
    dischtime,
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_admission
  FROM ugib_admissions
),
filtered_patients AS (
  SELECT 
    hadm_id,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days
  FROM age_calculated
  WHERE age_at_admission BETWEEN 84 AND 94
)
SELECT 
  APPROX_QUANTILES(los_days, 1000)[SAFE_OFFSET(750)] - 
  APPROX_QUANTILES(los_days, 1000)[SAFE_OFFSET(250)] AS iqr_los
FROM filtered_patients;