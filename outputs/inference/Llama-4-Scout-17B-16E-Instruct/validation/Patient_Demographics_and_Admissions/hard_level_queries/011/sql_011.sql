WITH 
patients_filter AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.insurance,
    a.hadm_id,
    a.admission_location,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'Emergency'
    AND a.hospital_expire_flag = 0  
),

hemorrhagic_stroke AS (
  SELECT 
    di.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE 
    di.seq_num = 1  
    AND (di.icd_code LIKE '430%' OR di.icd_code LIKE 'I60%')  
)

SELECT 
  COUNT(DISTINCT pf.hadm_id) AS num_admissions
FROM 
  patients_filter pf
JOIN 
  hemorrhagic_stroke hs 
  ON 
    pf.hadm_id = hs.hadm_id;