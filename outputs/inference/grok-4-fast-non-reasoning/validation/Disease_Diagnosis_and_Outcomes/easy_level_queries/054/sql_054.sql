WITH stroke_cohort AS (
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
    ON a.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code 
    AND d.icd_version = icd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND p.dod IS NULL
    AND a.hospital_expire_flag = 0
    AND d.seq_num = 1
    AND d.icd_version = 10
    AND d.icd_code LIKE 'I61%'
    AND a.dischtime > a.admittime
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
)
SELECT 
  STDDEV(los_days) AS sd_los_days
FROM 
  stroke_cohort
WHERE 
  los_days IS NOT NULL;