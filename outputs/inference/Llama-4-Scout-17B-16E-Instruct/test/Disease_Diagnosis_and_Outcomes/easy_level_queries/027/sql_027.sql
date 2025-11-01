WITH 
  -- Filter patients by age and gender
  target_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 49 AND 59
  ),
  
  -- Identify admissions with primary diagnosis of upper GI bleed
  upper_gi_bleed_admissions AS (
    SELECT a.hadm_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` i ON d.icd_code = i.icd_code AND d.icd_version = i.icd_version
    WHERE d.seq_num = 1 AND i.long_title LIKE '%Upper GI bleed%'
    AND a.subject_id IN (SELECT subject_id FROM target_patients)
  )

-- Calculate maximum length of stay
SELECT 
  MAX(DATE_DIFF(dischtime, admittime, DAY)) AS max_length_of_stay
FROM upper_gi_bleed_admissions;