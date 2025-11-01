WITH upper_gi_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    -- ICD-10 Codes
    (icd_version = 10 AND (
        REGEXP_CONTAINS(icd_code, r'^K25[0-9]') OR 
        REGEXP_CONTAINS(icd_code, r'^K26[0-9]') OR 
        REGEXP_CONTAINS(icd_code, r'^K27[0-9]') OR 
        REGEXP_CONTAINS(icd_code, r'^K28[0-9]') OR 
        icd_code IN ('K22.6', 'I85.01', 'I85.11')
    )) OR 
    -- ICD-9 Codes
    (icd_version = 9 AND (
        REGEXP_CONTAINS(icd_code, r'^531') OR 
        REGEXP_CONTAINS(icd_code, r'^532') OR 
        REGEXP_CONTAINS(icd_code, r'^533') OR 
        REGEXP_CONTAINS(icd_code, r'^534') OR 
        icd_code IN ('530.7', '456.0', '456.20')
    ))
),
major_comp_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    -- ICD-10: Shock, AKI, MI, Stroke
    (icd_version = 10 AND (
        REGEXP_CONTAINS(icd_code, r'^R57') OR 
        REGEXP_CONTAINS(icd_code, r'^N17') OR 
        REGEXP_CONTAINS(icd_code, r'^I21|I22') OR 
        REGEXP_CONTAINS(icd_code, r'^I6[0-3]')
    )) OR 
    -- ICD-9: Shock, AKI, MI, Stroke
    (icd_version = 9 AND (
        REGEXP_CONTAINS(icd_code, r'^785.5') OR 
        REGEXP_CONTAINS(icd_code, r'^584') OR 
        REGEXP_CONTAINS(icd_code, r'^410') OR 
        icd_code IN ('430', '431', '432.9', '436') OR 
        REGEXP_CONTAINS(icd_code, r'^433.[0-9]1|^434.[0-9]1')
    ))
),
cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.deathtime,  -- Added for mortality calculation
    adm.hospital_expire_flag,
    p.gender, 
    p.anchor_age, 
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 64 AND 74
    AND adm.dischtime IS NOT NULL  -- Exclude ongoing admissions
),
upper_gi_admissions AS (
  SELECT DISTINCT c.*
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON c.hadm_id = diag.hadm_id
  INNER JOIN upper_gi_codes gi
    ON diag.icd_code = gi.icd_code 
    AND diag.icd_version = gi.icd_version
),
diagnosis_counts AS (
  SELECT 
    hadm_id, 
    COUNT(DISTINCT icd_code) AS diagnosis_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
major_complications AS (
  SELECT 
    diag.hadm_id, 
    MAX(1) AS major_complication  -- Binary flag (1 if any complication exists)
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN major_comp_codes comp
    ON diag.icd_code = comp.icd_code 
    AND diag.icd_version = comp.icd_version
  GROUP BY diag.hadm_id
),
cohort_metrics AS (
  SELECT 
    uga.*,
    COALESCE(dc.diagnosis_count, 0) AS diagnosis_count,
    COALESCE(mc.major_complication, 0) AS major_complication,
    -- Composite Risk Score
    COALESCE(dc.diagnosis_count, 0) + 20 * COALESCE(mc.major_complication, 0) AS composite_score,
    -- 30-Day Mortality
    CASE 
      WHEN uga.hospital_expire_flag = 1 AND uga.deathtime <= DATETIME_ADD(uga.admittime, INTERVAL 30 DAY) THEN 1
      WHEN uga.hospital_expire_flag = 0 AND uga.dod <= DATE_ADD(DATE(uga.admittime), INTERVAL 30 DAY) THEN 1
      ELSE 0 
    END AS mortality_30d,
    -- LOS for survivors (NULL if died in hospital)
    CASE 
      WHEN uga.hospital_expire_flag = 0 THEN DATETIME_DIFF(uga.dischtime, uga.admittime, DAY) 
      ELSE NULL 
    END AS los_survivor
  FROM upper_gi_admissions uga
  LEFT JOIN diagnosis_counts dc
    ON uga.hadm_id = dc.hadm_id
  LEFT JOIN major_complications mc
    ON uga.hadm_id = mc.hadm_id
),
quintiles AS (
  SELECT *,
    NTILE(5) OVER (ORDER BY composite_score) AS quintile
  FROM cohort_metrics
)
SELECT 
  quintile,
  COUNT(*) AS n,
  ROUND(AVG(composite_score), 1) AS mean_score,
  ROUND(100 * AVG(mortality_30d), 1) AS mortality_30d_percent,
  ROUND(100 * AVG(major_complication), 1) AS major_complication_percent,
  ROUND(MEDIAN(los_survivor), 1) AS median_los_survivors  -- Replaced with MEDIAN()
FROM quintiles
GROUP BY quintile
ORDER BY quintile;