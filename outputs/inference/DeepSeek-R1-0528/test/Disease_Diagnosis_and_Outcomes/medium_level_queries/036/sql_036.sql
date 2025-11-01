WITH comorb_map AS (
  -- Mapping of ICD codes to comorbidity conditions
  SELECT icd_code, icd_version, condition
  FROM (
    -- Chronic Kidney Disease (CKD)
    SELECT '5859' AS icd_code, 9 AS icd_version, 'CKD' AS condition UNION ALL
    SELECT '586' AS icd_code, 9 AS icd_version, 'CKD' AS condition UNION ALL
    SELECT 'N18' AS icd_code, 10 AS icd_version, 'CKD' AS condition UNION ALL
    SELECT 'N19' AS icd_code, 10 AS icd_version, 'CKD' AS condition UNION ALL
    -- Diabetes
    SELECT '25000' AS icd_code, 9 AS icd_version, 'Diabetes' AS condition UNION ALL
    SELECT '25002' AS icd_code, 9 AS icd_version, 'Diabetes' AS condition UNION ALL
    SELECT 'E10' AS icd_code, 10 AS icd_version, 'Diabetes' AS condition UNION ALL
    SELECT 'E11' AS icd_code, 10 AS icd_version, 'Diabetes' AS condition UNION ALL
    -- Chronic Pulmonary Disease (COPD)
    SELECT '491' AS icd_code, 9 AS icd_version, 'COPD' AS condition UNION ALL
    SELECT '492' AS icd_code, 9 AS icd_version, 'COPD' AS condition UNION ALL
    SELECT 'J44' AS icd_code, 10 AS icd_version, 'COPD' AS condition UNION ALL
    -- Liver Disease
    SELECT '571' AS icd_code, 9 AS icd_version, 'Liver' AS condition UNION ALL
    SELECT 'K70' AS icd_code, 10 AS icd_version, 'Liver' AS condition UNION ALL
    SELECT 'K76' AS icd_code, 10 AS icd_version, 'Liver' AS condition UNION ALL
    -- Cancer
    SELECT '140' AS icd_code, 9 AS icd_version, 'Cancer' AS condition UNION ALL
    SELECT 'C0' AS icd_code, 10 AS icd_version, 'Cancer' AS condition UNION ALL
    SELECT 'C1' AS icd_code, 10 AS icd_version, 'Cancer' AS condition UNION ALL
    -- Cerebrovascular Disease
    SELECT '430' AS icd_code, 9 AS icd_version, 'Cerebrovascular' AS condition UNION ALL
    SELECT '438' AS icd_code, 9 AS icd_version, 'Cerebrovascular' AS condition UNION ALL
    SELECT 'I6' AS icd_code, 10 AS icd_version, 'Cerebrovascular' AS condition
  )
),
cohort AS (
  -- Base cohort: Females aged 39-49 with HF
  SELECT 
    p.subject_id, 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND a.hadm_id IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE 
        -- Heart Failure codes: ICD-9 '428%' or ICD-10 'I50%'
        (di.icd_version = 9 AND di.icd_code LIKE '428%')
        OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
    )
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 39 AND 49
),
cohort_comorb AS (
  -- Add comorbidity count, CKD, and diabetes flags
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.los,
    c.hospital_expire_flag,
    COUNT(DISTINCT map.condition) AS comorbidity_count,
    MAX(CASE WHEN map.condition = 'CKD' THEN 1 ELSE 0 END) AS ckd_flag,
    MAX(CASE WHEN map.condition = 'Diabetes' THEN 1 ELSE 0 END) AS diabetes_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON c.hadm_id = di.hadm_id
  LEFT JOIN comorb_map map
    ON di.icd_code = map.icd_code AND di.icd_version = map.icd_version
  GROUP BY c.subject_id, c.hadm_id, c.los, c.hospital_expire_flag
),
cohort_tertiles AS (
  -- Split into comorbidity tertiles
  SELECT *,
    NTILE(3) OVER (ORDER BY comorbidity_count) AS comorb_tertile
  FROM cohort_comorb
)
-- Final aggregation
SELECT 
  CASE 
    WHEN los <= 5 THEN '<=5' 
    ELSE '>5' 
  END AS los_group,
  CASE comorb_tertile
    WHEN 1 THEN 'Low'
    WHEN 2 THEN 'Med'
    WHEN 3 THEN 'High'
  END AS comorb_tertile_group,
  COUNT(*) AS n,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS in_hospital_mortality_percent,
  ROUND(SUM(ckd_flag) * 100.0 / COUNT(*), 2) AS ckd_prevalence_percent,
  ROUND(SUM(diabetes_flag) * 100.0 / COUNT(*), 2) AS diabetes_prevalence_percent
FROM cohort_tertiles
GROUP BY los_group, comorb_tertile_group
ORDER BY los_group, comorb_tertile_group;