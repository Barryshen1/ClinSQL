WITH 
  -- Identify AKI ICD codes
  aki_codes AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE long_title LIKE '%Acute kidney injury%'
  ),
  
  -- Filter patients with primary AKI admission
  aki_patients AS (
    SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
    WHERE p.gender = 'M' 
      AND p.anchor_age BETWEEN 52 AND 62
      AND d.icd_code IN (SELECT icd_code FROM aki_codes)
      AND d.seq_num = 1  -- Primary diagnosis
  ),
  
  -- Calculate hospital length of stay
  los AS (
    SELECT 
      TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
    FROM aki_patients
  )

-- Calculate 75th percentile of hospital length of stay
SELECT 
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los_days) AS percentile_75_los
FROM los;