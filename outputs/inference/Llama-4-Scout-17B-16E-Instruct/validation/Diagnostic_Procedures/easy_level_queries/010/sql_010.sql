WITH 
  -- Filter patients by age and gender
  target_patients AS (
    SELECT a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
    WHERE p.anchor_age BETWEEN 84 AND 94
    AND p.gender = 'M'
  ),
  
  -- Identify echocardiography procedures
  echo_procedures AS (
    SELECT p.subject_id, p.hadm_id, p.icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    WHERE d.long_title LIKE '%Echocardiography%'
  ),

  -- Count distinct procedures per patient
  patient_echo_count AS (
    SELECT p.subject_id, COUNT(DISTINCT p.icd_code) AS echo_count
    FROM echo_procedures p
    WHERE p.hadm_id IN (SELECT hadm_id FROM target_patients)
    GROUP BY p.subject_id
  )

-- Find the maximum count
SELECT MAX(echo_count) AS max_echo_count
FROM patient_echo_count;