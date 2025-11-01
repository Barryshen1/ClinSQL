WITH base_cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Calculate LOS in days (fractional)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
),
stroke_diagnoses AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND (icd_code LIKE '430%' OR icd_code LIKE '431%' OR icd_code LIKE '432%'))
    OR
    (icd_version = 10 AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%'))
),
copd_diagnoses AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 10 AND icd_code = 'J441')
    OR
    (icd_version = 9 AND icd_code = '49121')
),
eligible_patients AS (
  SELECT 
    b.los_days
  FROM base_cohort b
  INNER JOIN stroke_diagnoses s ON b.hadm_id = s.hadm_id
  INNER JOIN copd_diagnoses c ON b.hadm_id = c.hadm_id
  WHERE 
    b.age_at_admission BETWEEN 58 AND 68
)
SELECT 
  APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] - APPROX_QUANTILES(los_days, 1000)[OFFSET(250)] AS iqr
FROM eligible_patients;