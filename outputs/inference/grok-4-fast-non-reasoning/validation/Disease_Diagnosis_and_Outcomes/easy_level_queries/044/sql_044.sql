WITH filtered_patients AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 61 AND 71
),
heart_failure_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    filtered_patients fp ON a.subject_id = fp.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE 
    d.seq_num = 1
    AND d.icd_code LIKE 'I50%'
    AND d.icd_version = '10'  -- Focus on ICD-10 for modern admissions
    AND a.dischtime > a.admittime  -- Ensure valid LOS
)
SELECT 
  AVG(los_days) AS avg_los_days
FROM 
  heart_failure_admissions;