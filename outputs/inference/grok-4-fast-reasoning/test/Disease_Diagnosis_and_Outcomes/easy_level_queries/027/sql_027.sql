WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_icd
    ON a.subject_id = diag_icd.subject_id 
    AND a.hadm_id = diag_icd.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON diag_icd.icd_code = d_icd.icd_code 
    AND diag_icd.icd_version = d_icd.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND diag_icd.seq_num = 1
    AND LOWER(d_icd.long_title) LIKE '%hemorrhage%'
    AND (
      LOWER(d_icd.long_title) LIKE '%esophagus%' 
      OR LOWER(d_icd.long_title) LIKE '%stomach%' 
      OR LOWER(d_icd.long_title) LIKE '%gastric%' 
      OR LOWER(d_icd.long_title) LIKE '%duodenal%' 
      OR LOWER(d_icd.long_title) LIKE '%varices%'
    )
)
SELECT 
  MAX(los_days) AS max_los_days
FROM 
  cohort;