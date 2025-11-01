WITH stroke_patients AS (
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code 
    AND d.icd_version = icd.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND d.seq_num = 1
    AND d.icd_version = 10
    AND (
      d.icd_code LIKE 'I60%' OR 
      d.icd_code LIKE 'I61%' OR 
      d.icd_code LIKE 'I62%'
    )
    AND icd.long_title LIKE '%hemorrhag%'
    AND a.hospital_expire_flag = 0
    AND a.dischtime > a.admittime  -- Ensure valid LOS
)

SELECT 
  ANY_VALUE(PERCENT_CONT(0.75) OVER (ORDER BY los_days)) AS p75_hospital_los_days
FROM stroke_patients;