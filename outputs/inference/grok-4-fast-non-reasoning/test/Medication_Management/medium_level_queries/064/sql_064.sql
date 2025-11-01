WITH cohort AS (
  -- Base cohort: males aged 71-81 with admissions
  SELECT 
    CAST(p.subject_id AS STRING) AS subject_id,
    CAST(a.hadm_id AS STRING) AS hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.anchor_age BETWEEN 71 AND 81
    AND p.gender = 'M'
),

diabetes AS (
  -- Diabetes diagnoses (any seq_num)
  SELECT DISTINCT 
    CAST(subject_id AS STRING) AS subject_id,
    CAST(hadm_id AS STRING) AS hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^250'))
     OR (di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^E[1-4][0-9]'))
),

heart_failure AS (
  -- Acute heart failure diagnoses (any seq_num)
  SELECT DISTINCT 
    CAST(subject_id AS STRING) AS subject_id,
    CAST(hadm_id AS STRING) AS hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^428'))
     OR (di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^I50'))
),

qualified_admissions AS (
  -- Admissions with both conditions
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.los_hours
  FROM cohort c
  INNER JOIN diabetes d ON c.subject_id = d.subject_id AND c.hadm_id = d.hadm_id
  INNER JOIN heart_failure hf ON c.subject_id = hf.subject_id AND c.hadm_id = hf.hadm_id
  WHERE c.dischtime > c.admittime  -- Valid admission
    AND c.los_hours > 0
),

prescriptions_with_time AS (
  -- Add timing relative to admission
  SELECT 
    qa.hadm_id,
    pr.drug,
    pr.starttime,
    -- First 72h flag
    CASE 
      WHEN pr.starttime >= qa.admittime 
           AND pr.starttime < TIMESTAMP_ADD(qa.admittime, INTERVAL 72 HOUR)
      THEN 1 ELSE 0 
    END AS in_first_72h,
    -- Last 48h flag (if LOS >= 48h)
    CASE 
      WHEN qa.los_hours >= 48 
           AND pr.starttime >= TIMESTAMP_ADD(qa.admittime, INTERVAL (qa.los_hours - 48) HOUR)
           AND pr.starttime < qa.dischtime
      THEN 1 ELSE 0 
    END AS in_last_48h
  FROM qualified_admissions qa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON qa.hadm_id = pr.hadm_id
  WHERE pr.drug IS NOT NULL 
    AND LOWER(TRIM(pr.drug)) != ''
    AND pr.starttime IS NOT NULL
      AND pr.starttime >= qa.admittime  -- After admission start
      AND pr.starttime < COALESCE(qa.dischtime, TIMESTAMP_ADD(qa.admittime, INTERVAL 30 DAY))  -- Within admission or reasonable bound
),

drug_classes AS (
  -- Assign first initiation per class per admission
  SELECT 
    hadm_id,
    CASE 
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(drug) LIKE '%glyburide%' OR LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glimepiride%' 
           OR LOWER(drug) LIKE '%tolbutamide%' OR LOWER(drug) LIKE '%chlorpropamide%' THEN 'Sulfonylureas'
      WHEN LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%saxagliptin%' OR LOWER(drug) LIKE '%linagliptin%' 
           OR LOWER(drug) LIKE '%alogliptin%' THEN 'DPP-4'
      WHEN LOWER(drug) LIKE '%canagliflozin%' OR LOWER(drug) LIKE '%dapagliflozin%' OR LOWER(drug) LIKE '%empagliflozin%' 
           OR LOWER(drug) LIKE '%ertugliflozin%' THEN 'SGLT2'
      WHEN LOWER(drug) LIKE '%pioglitazone%' OR LOWER(drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinediones'
      ELSE NULL 
    END AS drug_class,
    in_first_72h,
    in_last_48h,
    ROW_NUMBER() OVER (PARTITION BY hadm_id, 
      CASE 
        WHEN LOWER(drug) LIKE '%metformin%' THEN 'Metformin'
        WHEN LOWER(drug) LIKE '%glyburide%' OR LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glimepiride%' 
             OR LOWER(drug) LIKE '%tolbutamide%' OR LOWER(drug) LIKE '%chlorpropamide%' THEN 'Sulfonylureas'
        WHEN LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%saxagliptin%' OR LOWER(drug) LIKE '%linagliptin%' 
             OR LOWER(drug) LIKE '%alogliptin%' THEN 'DPP-4'
        WHEN LOWER(drug) LIKE '%canagliflozin%' OR LOWER(drug) LIKE '%dapagliflozin%' OR LOWER(drug) LIKE '%empagliflozin%' 
             OR LOWER(drug) LIKE '%ertugliflozin%' THEN 'SGLT2'
        WHEN LOWER(drug) LIKE '%pioglitazone%' OR LOWER(drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinediones'
      END 
      ORDER BY starttime ASC) AS rn  -- Earliest starttime for initiation
  FROM prescriptions_with_time
  WHERE LOWER(drug) LIKE '%metformin%' 
     OR LOWER(drug) LIKE '%glyburide%' OR LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glimepiride%' 
     OR LOWER(drug) LIKE '%tolbutamide%' OR LOWER(drug) LIKE '%chlorpropamide%'
     OR LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%saxagliptin%' OR LOWER(drug) LIKE '%linagliptin%' 
     OR LOWER(drug) LIKE '%alogliptin%'
     OR LOWER(drug) LIKE '%canagliflozin%' OR LOWER(drug) LIKE '%dapagliflozin%' OR LOWER(drug) LIKE '%empagliflozin%' 
     OR LOWER(drug) LIKE '%ertugliflozin%'
     OR LOWER(drug) LIKE '%pioglitazone%' OR LOWER(drug) LIKE '%rosiglitazone%'
),

initiated AS (
  SELECT 
    drug_class,
    SUM(in_first_72h) AS initiated_first_72h,
    SUM(in_last_48h) AS initiated_last_48h,
    COUNT(DISTINCT hadm_id) AS total_admissions
  FROM drug_classes
  WHERE rn = 1 AND drug_class IS NOT NULL
  GROUP BY drug_class
)

-- Final rates (%)
SELECT 
  drug_class,
  ROUND((initiated_first_72h * 100.0 / total_admissions), 2) AS initiation_rate_first_72h_pct,
  ROUND((initiated_last_48h * 100.0 / total_admissions), 2) AS initiation_rate_last_48h_pct,
  total_admissions
FROM initiated
ORDER BY drug_class;