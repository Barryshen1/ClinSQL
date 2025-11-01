WITH filtered_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.insurance,
    a.admission_location,
    p.gender,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 46 AND 56
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'TRANSFER FROM HOSP/OTHER FACILITY'
),
principal_diagnoses AS (
  SELECT 
    di.hadm_id,
    di.icd_code,
    dicd.long_title,
    ROW_NUMBER() OVER (PARTITION BY di.hadm_id ORDER BY di.seq_num) AS diagnosis_priority
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE 
    di.hadm_id IN (SELECT hadm_id FROM filtered_admissions)
),
hip_fracture_admissions AS (
  SELECT 
    hadm_id
  FROM 
    principal_diagnoses
  WHERE 
    diagnosis_priority = 1
    AND LOWER(long_title) LIKE '%hip fracture%'  
)
SELECT 
  COUNT(*) AS num_admissions
FROM 
  hip_fracture_admissions;