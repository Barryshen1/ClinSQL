WITH qualifying_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND a.admission_type IN ('ELECTIVE', 'URGENT', 'EMERGENCY')
    AND CAST(d.seq_num AS STRING) = '1'
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'I2%'
    AND a.dischtime IS NOT NULL
)

SELECT 
  AVG(los_days) AS avg_hospital_los_days
FROM 
  qualifying_admissions;