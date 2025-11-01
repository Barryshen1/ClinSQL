WITH stroke_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 84 AND 94
    AND d.seq_num = 1
    AND d.icd_version = 10
    AND d.icd_code LIKE 'I63%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.admittime < a.dischtime
    AND a.hadm_id IS NOT NULL
)
SELECT 
  MAX(los_days) AS max_hospital_los_days
FROM 
  stroke_admissions;