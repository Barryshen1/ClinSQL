WITH cohort AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    diag.long_title
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` icd 
    ON a.hadm_id = icd.hadm_id AND icd.seq_num = 1
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag 
    ON icd.icd_code = diag.icd_code 
    AND icd.icd_version = diag.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND (LOWER(diag.long_title) LIKE '%sepsis%' OR LOWER(diag.long_title) LIKE '%septic shock%')
    AND a.dischtime IS NOT NULL
)
SELECT 
  STDDEV(DATE_DIFF(dischtime, admittime, DAY)) AS sd_los_days
FROM cohort;