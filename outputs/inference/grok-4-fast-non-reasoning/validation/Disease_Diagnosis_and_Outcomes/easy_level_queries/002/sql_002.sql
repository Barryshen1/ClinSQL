WITH aki_cohort AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
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
    AND p.anchor_age BETWEEN 52 AND 62
    AND p.anchor_age = 57  -- Filter for 57-year-old male within cohort
    AND d.seq_num = 1
    AND d.icd_code LIKE 'N17%'
    AND icd.icd_version = '10'  -- Focus on ICD-10 for AKI
    AND a.hospital_expire_flag = 0
    AND a.dischtime > a.admittime  -- Valid LOS
)

SELECT 
  PERCENTILE_CONT(0.75 IGNORE NULLS) OVER() AS p75_los_days
FROM 
  aki_cohort;