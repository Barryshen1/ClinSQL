WITH 
-- Define the population of interest
population AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hospital_length_of_stay
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.hospital_expire_flag = 0  -- Ensure the patient did not expire
),

-- Identify primary sepsis/septic shock
sepsis_population AS (
  SELECT 
    p.hadm_id,
    p.admittime,
    p.dischtime,
    p.hospital_length_of_stay
  FROM 
    population p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON p.hadm_id = d.hadm_id
  WHERE 
    (d.icd_code LIKE 'A40%' 
    OR d.icd_code LIKE 'A41%' 
    OR d.icd_code = 'R65.1'
    OR d.icd_code = 'R65.20'
    OR d.icd_code = 'R65.21')
    AND d.seq_num = 1  -- Primary diagnosis
)

-- Find maximum hospital length of stay
SELECT 
  MAX(hospital_length_of_stay) AS max_hospital_length_of_stay
FROM 
  sepsis_population;