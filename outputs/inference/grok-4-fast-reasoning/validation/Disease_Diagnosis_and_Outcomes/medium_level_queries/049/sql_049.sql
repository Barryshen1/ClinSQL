WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.gender,
    p.anchor_age,
    d.icd_version,
    d.icd_code,
    CASE 
      WHEN (d.icd_version = 'ICD-9' AND (d.icd_code LIKE '410.0%' OR d.icd_code LIKE '410.1%' OR d.icd_code LIKE '410.2%' OR d.icd_code LIKE '410.6%'))
        OR (d.icd_version = 'ICD-10' AND (d.icd_code LIKE 'I21.0%' OR d.icd_code LIKE 'I21.1%' OR d.icd_code LIKE 'I21.2%' OR d.icd_code LIKE 'I21.3%'))
      THEN 'STEMI'
      WHEN (d.icd_version = 'ICD-9' AND (d.icd_code LIKE '410.3%' OR d.icd_code LIKE '410.4%' OR d.icd_code LIKE '410.7%' OR d.icd_code LIKE '410.9%'))
        OR (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'I21.4%')
      THEN 'NSTEMI'
    END AS mi_type
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id AND d.seq_num = '1'
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND a.dischtime IS NOT NULL
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) >= 0
),
comorb AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.los_days,
    c.mi_type,
    MAX(CASE 
      WHEN (diag.icd_version = 'ICD-9' AND diag.icd_code LIKE '250.%') 
        OR (diag.icd_version = 'ICD-10' AND (diag.icd_code LIKE 'E10%' OR diag.icd_code LIKE 'E11%' OR diag.icd_code LIKE 'E12%' OR diag.icd_code LIKE 'E13%' OR diag.icd_code LIKE 'E14%')) 
      THEN 1 ELSE 0 
    END) AS has_diabetes,
    MAX(CASE 
      WHEN (diag.icd_version = 'ICD-9' AND (diag.icd_code LIKE '585.%' OR diag.icd_code = '586')) 
        OR (diag.icd_version = 'ICD-10' AND diag.icd_code LIKE 'N18%') 
      THEN 1 ELSE 0 
    END) AS has_ckd,
    MAX(CASE 
      WHEN (diag.icd_version = 'ICD-9' AND diag.icd_code LIKE '428.%') 
        OR (diag.icd_version = 'ICD-10' AND diag.icd_code LIKE 'I50%') 
      THEN 1 ELSE 0 
    END) AS has_hf,
    MAX(CASE 
      WHEN (diag.icd_version = 'ICD-9' AND (diag.icd_code LIKE '401%' OR diag.icd_code LIKE '402%' OR diag.icd_code LIKE '403%' OR diag.icd_code LIKE '404%' OR diag.icd_code LIKE '405%')) 
        OR (diag.icd_version = 'ICD-10' AND (diag.icd_code LIKE 'I10%' OR diag.icd_code LIKE 'I11%' OR diag.icd_code LIKE 'I12%' OR diag.icd_code LIKE 'I13%' OR diag.icd_code LIKE 'I15%' OR diag.icd_code LIKE 'I16%')) 
      THEN 1 ELSE 0 
    END) AS has_htn,
    MAX(CASE 
      WHEN (diag.icd_version = 'ICD-9' AND (diag.icd_code LIKE '490%' OR diag.icd_code LIKE '491%' OR diag.icd_code LIKE '492%' OR diag.icd_code LIKE '493%' OR diag.icd_code LIKE '494%' OR diag.icd_code LIKE '495%' OR diag.icd_code LIKE '496%')) 
        OR (diag.icd_version = 'ICD-10' AND (diag.icd_code LIKE 'J40%' OR diag.icd_code LIKE 'J41%' OR diag.icd_code LIKE 'J42%' OR diag.icd_code LIKE 'J43%' OR diag.icd_code LIKE 'J44%' OR diag.icd_code LIKE 'J47%')) 
      THEN 1 ELSE 0 
    END) AS has_copd
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
    ON c.hadm_id = diag.hadm_id
  WHERE c.mi_type IS NOT NULL
  GROUP BY 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime, 
    c.hospital_expire_flag, c.los_days, c.mi_type
),
with_groups AS (
  SELECT *,
    CASE 
      WHEN los_days BETWEEN 1 AND 2 THEN '1-2'
      WHEN los_days BETWEEN 3 AND 5 THEN '3-5'
      WHEN los_days BETWEEN 6 AND 9 THEN '6-9'
      WHEN los_days >= 10 THEN '>=10'
      ELSE 'Other' 
    END AS los_group,
    (has_diabetes + has_ckd + has_hf + has_htn + has_copd) AS num_comorb,
    CASE 
      WHEN (has_diabetes + has_ckd + has_hf + has_htn + has_copd) <= 1 THEN '0-1'
      WHEN (has_diabetes + has_ckd + has_hf + has_htn + has_copd) = 2 THEN '2'
      ELSE '>=3'
    END AS comorb_group
  FROM comorb
  WHERE los_days >= 1
)
SELECT 
  mi_type,
  los_group,
  comorb_group,
  COUNT(*) AS N,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
  ROUND(AVG(has_diabetes) * 100, 2) AS diabetes_prevalence_pct,
  ROUND(AVG(has_ckd) * 100, 2) AS ckd_prevalence_pct
FROM with_groups
GROUP BY mi_type, los_group, comorb_group
ORDER BY mi_type, los_group, comorb_group;