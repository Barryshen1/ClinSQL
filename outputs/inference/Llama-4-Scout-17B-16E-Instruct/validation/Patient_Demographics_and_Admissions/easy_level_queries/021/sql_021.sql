WITH 
-- Identify patients of interest
patients_of_interest AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    d.icd_code
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND d.icd_code LIKE 'Pneumonia%'  -- Assuming pneumonia ICD code contains 'Pneumonia'
),

-- Identify first admission for each patient
first_admission AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM 
    patients_of_interest
)

-- Calculate in-hospital mortality for first admissions
SELECT 
  COUNT(CASE WHEN hospital_expire_flag = 1 THEN hadm_id END) AS deaths,
  COUNT(hadm_id) AS total_admissions,
  IF(COUNT(hadm_id) = 0, 0, 
     COUNT(CASE WHEN hospital_expire_flag = 1 THEN hadm_id END) * 100.0 / COUNT(hadm_id)) AS mortality_rate
FROM 
  first_admission
WHERE 
  rn = 1;