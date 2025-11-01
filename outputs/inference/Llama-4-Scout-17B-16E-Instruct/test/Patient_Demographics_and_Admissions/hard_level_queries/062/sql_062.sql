WITH acute_cholecystitis AS (
  SELECT 
    d.icd_code,
    d.long_title
  FROM 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  WHERE 
    d.long_title LIKE '%Acute cholecystitis%'
),
target_patients AS (
  SELECT 
    a.hadm_id,
    a.admit_provider_id,
    a.admission_location,
    a.insurance,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'Emergency Department'
),
index_admissions AS (
  SELECT 
    tp.hadm_id
  FROM 
    target_patients tp
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      ON tp.hadm_id = di.hadm_id
  JOIN 
    acute_cholecystitis ac 
      ON di.icd_code = ac.icd_code
  WHERE 
    di.seq_num = 1  -- Principal diagnosis
)
SELECT 
  COUNT(DISTINCT hadm_id) AS total_index_admissions
FROM 
  index_admissions;