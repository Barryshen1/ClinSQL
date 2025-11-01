WITH 
-- Calculate age at admission and filter for females 54-64
patients_age AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 54 AND 64
),

-- Identify patients with diabetes diagnoses
diabetes_diagnoses AS (
  SELECT DISTINCT
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
  WHERE 
    -- ICD-9 diabetes codes (250.x)
    (d.icd_version = 9 AND d.icd_code LIKE '250%')
    OR
    -- ICD-10 diabetes codes (E08, E09, E10, E11, E13)
    (d.icd_version = 10 AND (
      d.icd_code LIKE 'E08%' OR
      d.icd_code LIKE 'E09%' OR
      d.icd_code LIKE 'E10%' OR
      d.icd_code LIKE 'E11%' OR
      d.icd_code LIKE 'E13%'
    ))
),

-- Identify patients with heart failure diagnoses
heart_failure_diagnoses AS (
  SELECT DISTINCT
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
  WHERE 
    -- ICD-9 heart failure codes
    (d.icd_version = 9 AND (
      d.icd_code LIKE '428%' OR
      d.icd_code IN ('39891', '40201', '40211', '40291', '40401', '40403', '40411', '40413', '40491', '40493')
    ))
    OR
    -- ICD-10 heart failure codes (I50.x)
    (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
),

-- Combine to get the final cohort
cohort AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime
  FROM patients_age pa
  INNER JOIN diabetes_diagnoses dd ON pa.hadm_id = dd.hadm_id
  INNER JOIN heart_failure_diagnoses hfd ON pa.hadm_id = hfd.hadm_id
),

-- Identify medication administrations
medications AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    -- First 12 hours window (handles short admissions)
    CASE WHEN p.starttime BETWEEN c.admittime AND LEAST(DATETIME_ADD(c.admittime, INTERVAL 12 HOUR), c.dischtime) THEN 1 ELSE 0 END AS first_12h,
    -- Final 48 hours window (handles short admissions)
    CASE WHEN p.starttime BETWEEN GREATEST(DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR), c.admittime) AND c.dischtime THEN 1 ELSE 0 END AS final_48h,
    -- Insulin flag
    CASE WHEN LOWER(p.drug) LIKE '%insulin%' THEN 1 ELSE 0 END AS is_insulin,
    -- Oral agent flag
    CASE 
      WHEN LOWER(p.drug) LIKE '%metformin%' OR
           LOWER(p.drug) LIKE '%glipizide%' OR
           LOWER(p.drug) LIKE '%glyburide%' OR
           LOWER(p.drug) LIKE '%glimepiride%' OR
           LOWER(p.drug) LIKE '%sitagliptin%' OR
           LOWER(p.drug) LIKE '%saxagliptin%' OR
           LOWER(p.drug) LIKE '%linagliptin%' OR
           LOWER(p.drug) LIKE '%alogliptin%' OR
           LOWER(p.drug) LIKE '%empagliflozin%' OR
           LOWER(p.drug) LIKE '%canagliflozin%' OR
           LOWER(p.drug) LIKE '%dapagliflozin%' OR
           LOWER(p.drug) LIKE '%ertugliflozin%' OR
           LOWER(p.drug) LIKE '%pioglitazone%' OR
           LOWER(p.drug) LIKE '%rosiglitazone%' OR
           LOWER(p.drug) LIKE '%repaglinide%' OR
           LOWER(p.drug) LIKE '%nateglinide%' OR
           LOWER(p.drug) LIKE '%acarbose%' OR
           LOWER(p.drug) LIKE '%miglitol%' THEN 1 
      ELSE 0 
    END AS is_oral_agent
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions p
    ON c.hadm_id = p.hadm_id
  WHERE 
    -- Only consider relevant medications (insulin or oral agents)
    (LOWER(p.drug) LIKE '%insulin%' OR
     LOWER(p.drug) LIKE '%metformin%' OR
     LOWER(p.drug) LIKE '%glipizide%' OR
     LOWER(p.drug) LIKE '%glyburide%' OR
     LOWER(p.drug) LIKE '%glimepiride%' OR
     LOWER(p.drug) LIKE '%sitagliptin%' OR
     LOWER(p.drug) LIKE '%saxagliptin%' OR
     LOWER(p.drug) LIKE '%linagliptin%' OR
     LOWER(p.drug) LIKE '%alogliptin%' OR
     LOWER(p.drug) LIKE '%empagliflozin%' OR
     LOWER(p.drug) LIKE '%canagliflozin%' OR
     LOWER(p.drug) LIKE '%dapagliflozin%' OR
     LOWER(p.drug) LIKE '%ertugliflozin%' OR
     LOWER(p.drug) LIKE '%pioglitazone%' OR
     LOWER(p.drug) LIKE '%rosiglitazone%' OR
     LOWER(p.drug) LIKE '%repaglinide%' OR
     LOWER(p.drug) LIKE '%nateglinide%' OR
     LOWER(p.drug) LIKE '%acarbose%' OR
     LOWER(p.drug) LIKE '%miglitol%')
),

-- Aggregate medication usage by time window
aggregated AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN first_12h = 1 AND is_insulin = 1 THEN 1 ELSE 0 END) AS insulin_first_12h,
    MAX(CASE WHEN first_12h = 1 AND is_oral_agent = 1 THEN 1 ELSE 0 END) AS oral_first_12h,
    MAX(CASE WHEN final_48h = 1 AND is_insulin = 1 THEN 1 ELSE 0 END) AS insulin_final_48h,
    MAX(CASE WHEN final_48h = 1 AND is_oral_agent = 1 THEN 1 ELSE 0 END) AS oral_final_48h
  FROM medications
  GROUP BY hadm_id
)

-- Calculate prevalence rates and net change
SELECT
  COUNT(*) AS total_patients,
  -- Insulin prevalence
  SUM(insulin_first_12h) AS insulin_first_12h_count,
  ROUND(100.0 * SUM(insulin_first_12h) / COUNT(*), 2) AS insulin_first_12h_pct,
  SUM(insulin_final_48h) AS insulin_final_48h_count,
  ROUND(100.0 * SUM(insulin_final_48h) / COUNT(*), 2) AS insulin_final_48h_pct,
  ROUND(100.0 * SUM(insulin_final_48h) / COUNT(*) - 100.0 * SUM(insulin_first_12h) / COUNT(*), 2) AS insulin_net_change_pp,
  -- Oral agent prevalence
  SUM(oral_first_12h) AS oral_first_12h_count,
  ROUND(100.0 * SUM(oral_first_12h) / COUNT(*), 2) AS oral_first_12h_pct,
  SUM(oral_final_48h) AS oral_final_48h_count,
  ROUND(100.0 * SUM(oral_final_48h) / COUNT(*), 2) AS oral_final_48h_pct,
  ROUND(100.0 * SUM(oral_final_48h) / COUNT(*) - 100.0 * SUM(oral_first_12h) / COUNT(*), 2) AS oral_net_change_pp
FROM aggregated;