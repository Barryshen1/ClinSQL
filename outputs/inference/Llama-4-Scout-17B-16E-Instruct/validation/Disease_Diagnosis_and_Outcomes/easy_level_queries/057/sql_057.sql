WITH 
  -- Identify community-acquired pneumonia ICD codes
  cap_icd_codes AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE long_title LIKE '%Pneumonia%' AND long_title LIKE '%Community-acquired%'
  ),

  -- Filter relevant patients and admissions
  eligible_patients AS (
    SELECT a.hadm_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    WHERE p.gender = 'F' 
      AND p.anchor_age BETWEEN 88 AND 98
      AND a.dischtime IS NOT NULL  -- Ensure discharge time is not null
  ),

  -- Identify admissions with CAP as primary diagnosis
  cap_admissions AS (
    SELECT da.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` da
    JOIN cap_icd_codes cic
      ON da.icd_code = cic.icd_code
    WHERE da.seq_num = 1  -- Primary diagnosis
  )

SELECT 
  MIN(DATE_DIFF(ea.dischtime, ea.admittime, DAY)) AS min_hospital_los_days
FROM eligible_patients ea
JOIN cap_admissions ca 
  ON ea.hadm_id = ca.hadm_id;