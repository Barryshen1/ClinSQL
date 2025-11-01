WITH sepsis_admissions AS (
  SELECT DISTINCT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON 
    a.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
  ON 
    d.icd_code = icd.icd_code 
    AND d.icd_version = icd.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND d.seq_num = 1  -- Primary diagnosis
    AND d.icd_version = 10  -- ICD-10 for sepsis codes
    AND (d.icd_code LIKE 'A41%'  -- Sepsis
         OR d.icd_code LIKE 'R65%')  -- Severe sepsis/septic shock
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime  -- Valid LOS
)

SELECT 
  MAX(DATE_DIFF(DATE(dischtime), DATE(admittime), DAY)) AS max_hospital_los_days
FROM 
  sepsis_admissions;