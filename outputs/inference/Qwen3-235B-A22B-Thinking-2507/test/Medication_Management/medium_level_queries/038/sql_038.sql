WITH patient_cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 57 AND 67
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        -- Diabetes diagnosis (ICD-9 and ICD-10)
        (icd_version = 9 AND icd_code LIKE '250.%')
        OR (icd_version = 10 AND (icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' 
                                 OR icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' 
                                 OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%'))
    )
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        -- Acute HF diagnosis (specific ICD codes)
        (icd_version = 9 AND icd_code IN ('428.21', '428.22', '428.23', '428.41', '428.42', '428.43'))
        OR (icd_version = 10 AND icd_code IN ('I50.21', 'I50.22', 'I50.23', 'I50.41', 'I50.42', 'I50.43'))
    )
),

glp1_medications AS (
  SELECT 
    hadm_id,
    starttime AS order_time,
    -- Flag as first occurrence within admission
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY starttime) = 1 AS is_first_initiation
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    LOWER(drug) LIKE '%exenatide%' OR
    LOWER(drug) LIKE '%byetta%' OR
    LOWER(drug) LIKE '%bydureon%' OR
    LOWER(drug) LIKE '%liraglutide%' OR
    LOWER(drug) LIKE '%victoza%' OR
    LOWER(drug) LIKE '%saxenda%' OR
    LOWER(drug) LIKE '%dulaglutide%' OR
    LOWER(drug) LIKE '%trulicity%' OR
    LOWER(drug) LIKE '%semaglutide%' OR
    LOWER(drug) LIKE '%ozempic%' OR
    LOWER(drug) LIKE '%rybelsus%' OR
    LOWER(drug) LIKE '%lixisenatide%' OR
    LOWER(drug) LIKE '%adlyxin%' OR
    LOWER(drug) LIKE '%albiglutide%' OR
    LOWER(drug) LIKE '%tanzeum%'
),

cohort_with_glp1 AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    -- First 72 hours window
    CASE WHEN g.order_time BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR) 
         THEN 1 ELSE 0 END AS in_first_72h,
    -- Final 24 hours window
    CASE WHEN g.order_time BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime 
         THEN 1 ELSE 0 END AS in_final_24h,
    -- First initiation in first 72h
    CASE WHEN g.is_first_initiation = TRUE 
          AND g.order_time BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR) 
         THEN 1 ELSE 0 END AS initiation_first_72h,
    -- First initiation in final 24h
    CASE WHEN g.is_first_initiation = TRUE 
          AND g.order_time BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime 
         THEN 1 ELSE 0 END AS initiation_final_24h
  FROM patient_cohort c
  LEFT JOIN glp1_medications g ON c.hadm_id = g.hadm_id
)

SELECT
  -- Prevalence metrics
  ROUND(100.0 * SUM(CASE WHEN in_first_72h = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT hadm_id), 2) AS prevalence_first_72h,
  ROUND(100.0 * SUM(CASE WHEN in_final_24h = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT hadm_id), 2) AS prevalence_final_24h,
  ROUND(100.0 * SUM(CASE WHEN in_final_24h = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT hadm_id), 2) 
    - ROUND(100.0 * SUM(CASE WHEN in_first_72h = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT hadm_id), 2) AS abs_change_prevalence,
  ROUND((ROUND(100.0 * SUM(CASE WHEN in_final_24h = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(DISTINCT hadm_id), 0), 2) 
        - ROUND(100.0 * SUM(CASE WHEN in_first_72h = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(DISTINCT hadm_id), 0), 2))
        / NULLIF(ROUND(100.0 * SUM(CASE WHEN in_first_72h = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(DISTINCT hadm_id), 0), 2), 0), 4) AS rel_change_prevalence,
  
  -- Initiation rate metrics
  ROUND(100.0 * SUM(CASE WHEN initiation_first_72h = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT hadm_id), 2) AS initiation_first_72h,
  ROUND(100.0 * SUM(CASE WHEN initiation_final_24h = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT hadm_id), 2) AS initiation_final_24h,
  ROUND(100.0 * SUM(CASE WHEN initiation_final_24h = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT hadm_id), 2) 
    - ROUND(100.0 * SUM(CASE WHEN initiation_first_72h = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT hadm_id), 2) AS abs_change_initiation,
  ROUND((ROUND(100.0 * SUM(CASE WHEN initiation_final_24h = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(DISTINCT hadm_id), 0), 2) 
        - ROUND(100.0 * SUM(CASE WHEN initiation_first_72h = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(DISTINCT hadm_id), 0), 2))
        / NULLIF(ROUND(100.0 * SUM(CASE WHEN initiation_first_72h = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(DISTINCT hadm_id), 0), 2), 0), 4) AS rel_change_initiation
FROM cohort_with_glp1;