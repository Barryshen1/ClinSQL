WITH cohort_admissions AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    SUM(CASE WHEN d.icd_code LIKE 'I50.%' THEN 1 ELSE 0 END) OVER (PARTITION BY a.hadm_id) > 0 AS has_hf,
    SUM(CASE WHEN d.icd_code LIKE 'J44.%' THEN 1 ELSE 0 END) OVER (PARTITION BY a.hadm_id) > 0 AS has_copd
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
    AND p.anchor_age BETWEEN CAST(77 AS INT64) AND CAST(87 AS INT64)
    AND a.dischtime IS NOT NULL
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) > 0
    AND d.icd_version = 'ICD-10'
    AND d.seq_num >= 1  -- All diagnoses (primary and secondary)
)

SELECT 
  STDDEV(los_days) AS sd_hospital_los_days
FROM 
  cohort_admissions
WHERE has_hf AND has_copd;