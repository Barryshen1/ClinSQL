WITH pneumonia_cohort AS (
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
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
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND d.seq_num = CAST(1 AS INT64)
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'J1[2-8]%'
    AND a.hospital_expire_flag = 0
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) > 0
)

SELECT 
  PERCENTILE_CONT(0.25) OVER() AS p25_los_days
FROM 
  pneumonia_cohort;