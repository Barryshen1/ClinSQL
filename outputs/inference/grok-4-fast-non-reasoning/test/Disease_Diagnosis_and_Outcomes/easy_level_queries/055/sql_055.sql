WITH aki_cohort AS (
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days
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
    AND p.anchor_age BETWEEN 37 AND 47
    AND d.seq_num = 1
    AND d.icd_version = 10
    AND d.icd_code LIKE 'N17.%'
    AND icd.long_title LIKE '%acute kidney%'
    AND a.deathtime IS NULL
    AND (EXTRACT(DAY FROM (a.dischtime - a.admittime))) > 0
)
SELECT 
  PERCENTILE_CONT(los_days, 0.75) AS p75_los_days
FROM aki_cohort;