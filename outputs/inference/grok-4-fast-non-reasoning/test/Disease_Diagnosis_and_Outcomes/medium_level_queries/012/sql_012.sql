WITH cte_patients AS (
  -- Filter women aged 83-93
  SELECT DISTINCT 
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
),

cte_admissions AS (
  -- Base admissions with LOS and mortality
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN cte_patients pat ON a.subject_id = pat.subject_id
  WHERE a.admittime <= a.dischtime  -- Valid LOS
),

cte_hf AS (
  -- Heart failure admissions (principal diagnosis)
  SELECT DISTINCT 
    a.*,
    CASE WHEN icu.stay_id IS NOT NULL THEN 1 ELSE 0 END AS is_icu
  FROM cte_admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
    ON a.hadm_id = diag.hadm_id AND diag.seq_num = 1
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu 
    ON CAST(a.hadm_id AS STRING) = CAST(icu.hadm_id AS STRING)
  WHERE (diag.icd_code LIKE 'I50%' AND diag.icd_version = '10') 
     OR (diag.icd_code LIKE '428%' AND diag.icd_version = '9')
),

cte_comorbidities AS (
  -- Add comorbidity count (simplified: diabetes, CKD, HTN, CAD, COPD, AFib)
  SELECT 
    hf.*,
    COUNT(DISTINCT CASE 
      WHEN diag.icd_code LIKE 'E10%' OR diag.icd_code LIKE 'E11%' OR diag.icd_code LIKE 'E12%' OR 
           diag.icd_code LIKE 'E13%' OR diag.icd_code LIKE 'E14%' OR diag.icd_code LIKE '250%' THEN 1  -- Diabetes (ICD-10/9)
      WHEN diag.icd_code LIKE 'N18%' OR diag.icd_code LIKE '585%' THEN 1  -- CKD
      WHEN diag.icd_code LIKE 'I10%' OR diag.icd_code LIKE 'I11%' OR diag.icd_code LIKE 'I12%' OR 
           diag.icd_code LIKE 'I13%' OR diag.icd_code LIKE 'I15%' OR diag.icd_code LIKE '401%' OR 
           diag.icd_code LIKE '402%' OR diag.icd_code LIKE '403%' OR diag.icd_code LIKE '404%' THEN 1  -- HTN
      WHEN diag.icd_code LIKE 'I20%' OR diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%' OR 
           diag.icd_code LIKE 'I23%' OR diag.icd_code LIKE 'I24%' OR diag.icd_code LIKE 'I25%' THEN 1  -- CAD
      WHEN diag.icd_code LIKE 'J44%' OR diag.icd_code LIKE '491%' OR diag.icd_code LIKE '492%' OR 
           diag.icd_code LIKE '496%' THEN 1  -- COPD
      WHEN diag.icd_code LIKE 'I48%' OR diag.icd_code LIKE '427.3%' THEN 1  -- AFib
    END) AS comorb_count
  FROM cte_hf hf
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
    ON hf.hadm_id = diag.hadm_id
  GROUP BY 
    hf.subject_id, hf.hadm_id, hf.admittime, hf.dischtime, hf.hospital_expire_flag, 
    hf.los_days, hf.is_icu
),

cte_flags AS (
  -- Add CKD and diabetes flags per admission
  SELECT 
    com.*,
    MAX(CASE 
      WHEN diag.icd_code LIKE 'N18%' OR diag.icd_code LIKE '585%' THEN 1 ELSE 0 
    END) AS has_ckd,
    MAX(CASE 
      WHEN diag.icd_code LIKE 'E10%' OR diag.icd_code LIKE 'E11%' OR diag.icd_code LIKE 'E12%' OR 
           diag.icd_code LIKE 'E13%' OR diag.icd_code LIKE 'E14%' OR diag.icd_code LIKE '250%' THEN 1 ELSE 0 
    END) AS has_diabetes,
    CASE 
      WHEN comorb_count <= 1 THEN '0-1'
      WHEN comorb_count = 2 THEN '2'
      ELSE '>=3'
    END AS comorb_bucket,
    CASE 
      WHEN com.los_days < 8 THEN '<8'
      ELSE '>=8'
    END AS los_bucket
  FROM cte_comorbidities com
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
    ON com.hadm_id = diag.hadm_id
  GROUP BY 
    com.subject_id, com.hadm_id, com.admittime, com.dischtime, com.hospital_expire_flag, 
    com.los_days, com.is_icu, com.comorb_count
)

-- Final aggregations, stratified by ICU, LOS bucket, comorb bucket
SELECT 
  is_icu,
  los_bucket,
  comorb_bucket,
  COUNT(*) AS n_admissions,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
  PERCENTILE_CONT(los_days, 0.5) AS median_los_days,
  ROUND(AVG(has_ckd) * 100, 2) AS ckd_prevalence_pct,
  ROUND(AVG(has_diabetes) * 100, 2) AS diabetes_prevalence_pct
FROM cte_flags
GROUP BY is_icu, los_bucket, comorb_bucket
ORDER BY is_icu, los_bucket, comorb_bucket;