WITH stroke_cohort AS (
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
    ON a.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code 
    AND d.icd_version = icd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND d.seq_num = 1
    AND d.icd_version = 10
    AND d.icd_code LIKE 'I61%'
    AND a.hospital_expire_flag = 0
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) > 0
)

SELECT 
  STDDEV(los_days) AS sd_hospital_los_days
FROM 
  stroke_cohort;