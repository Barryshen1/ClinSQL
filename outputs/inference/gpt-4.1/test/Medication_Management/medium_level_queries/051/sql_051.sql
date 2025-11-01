WITH
-- 1. Select female patients aged 86–96
female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 86 AND 96
),

-- 2. Identify admissions with DM and HF
dm_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250')) OR
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E0[89]|^E1[0-3]'))
  )
),
hf_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^428')) OR
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I50'))
  )
),
dm_hf_admissions AS (
  SELECT a.subject_id, a.hadm_id, admittime, dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN female_patients p ON a.subject_id = p.subject_id
  JOIN dm_admissions dm ON a.hadm_id = dm.hadm_id
  JOIN hf_admissions hf ON a.hadm_id = hf.hadm_id
  WHERE TIMESTAMP_DIFF(dischtime, admittime, HOUR) >= 72 -- Ensure admission is long enough
),

-- 3. Drug class mapping
drug_classes AS (
  SELECT
    hadm_id,
    subject_id,
    starttime,
    stoptime,
    LOWER(drug) AS drug_lower,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'Oral'
      WHEN LOWER(drug) LIKE '%glyburide%' THEN 'Oral'
      WHEN LOWER(drug) LIKE '%glipizide%' THEN 'Oral'
      WHEN LOWER(drug) LIKE '%glimepiride%' THEN 'Oral'
      WHEN LOWER(drug) LIKE '%pioglitazone%' THEN 'Oral'
      WHEN LOWER(drug) LIKE '%sitagliptin%' THEN 'Oral'
      WHEN LOWER(drug) LIKE '%linagliptin%' THEN 'Oral'
      WHEN LOWER(drug) LIKE '%canagliflozin%' THEN 'Oral'
      WHEN LOWER(drug) LIKE '%dapagliflozin%' THEN 'Oral'
      WHEN LOWER(drug) LIKE '%empagliflozin%' THEN 'Oral'
      WHEN LOWER(drug) LIKE '%repaglinide%' THEN 'Oral'
      WHEN LOWER(drug) LIKE '%nateglinide%' THEN 'Oral'
      WHEN LOWER(drug) LIKE '%acarbose%' THEN 'Oral'
      WHEN LOWER(drug) LIKE '%miglitol%' THEN 'Oral'
      ELSE NULL
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%insulin%'
     OR LOWER(drug) LIKE '%metformin%'
     OR LOWER(drug) LIKE '%glyburide%'
     OR LOWER(drug) LIKE '%glipizide%'
     OR LOWER(drug) LIKE '%glimepiride%'
     OR LOWER(drug) LIKE '%pioglitazone%'
     OR LOWER(drug) LIKE '%sitagliptin%'
     OR LOWER(drug) LIKE '%linagliptin%'
     OR LOWER(drug) LIKE '%canagliflozin%'
     OR LOWER(drug) LIKE '%dapagliflozin%'
     OR LOWER(drug) LIKE '%empagliflozin%'
     OR LOWER(drug) LIKE '%repaglinide%'
     OR LOWER(drug) LIKE '%nateglinide%'
     OR LOWER(drug) LIKE '%acarbose%'
     OR LOWER(drug) LIKE '%miglitol%'
),

-- 4. For each admission, determine drug class exposure in early (first 12h) and late (final 72h)
drug_exposure AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    dc.drug_class,
    -- Early: any prescription with starttime in first 12h
    MAX(CASE WHEN dc.drug_class IS NOT NULL
      AND dc.starttime >= a.admittime
      AND dc.starttime < TIMESTAMP_ADD(a.admittime, INTERVAL 12 HOUR)
      THEN 1 ELSE 0 END) AS early_exposed,
    -- Late: any prescription with starttime in final 72h
    MAX(CASE WHEN dc.drug_class IS NOT NULL
      AND dc.starttime >= TIMESTAMP_SUB(a.dischtime, INTERVAL 72 HOUR)
      AND dc.starttime < a.dischtime
      THEN 1 ELSE 0 END) AS late_exposed
  FROM dm_hf_admissions a
  LEFT JOIN drug_classes dc
    ON a.hadm_id = dc.hadm_id
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, dc.drug_class
),

-- 5. Pivot to get per-admission early/late exposure for each class
admission_exposure AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(CASE WHEN drug_class = 'Insulin' THEN early_exposed ELSE 0 END) AS early_insulin,
    MAX(CASE WHEN drug_class = 'Oral' THEN early_exposed ELSE 0 END) AS early_oral,
    MAX(CASE WHEN drug_class = 'Insulin' THEN late_exposed ELSE 0 END) AS late_insulin,
    MAX(CASE WHEN drug_class = 'Oral' THEN late_exposed ELSE 0 END) AS late_oral
  FROM drug_exposure
  GROUP BY subject_id, hadm_id
),

-- 6. Calculate rates and transitions
summary AS (
  SELECT
    COUNT(*) AS n_admissions,
    SUM(early_insulin) AS n_early_insulin,
    SUM(early_oral) AS n_early_oral,
    SUM(late_insulin) AS n_late_insulin,
    SUM(late_oral) AS n_late_oral,
    -- Transitions
    SUM(CASE WHEN early_insulin=1 AND late_insulin=1 THEN 1 ELSE 0 END) AS n_insulin_to_insulin,
    SUM(CASE WHEN early_insulin=1 AND late_oral=1 THEN 1 ELSE 0 END) AS n_insulin_to_oral,
    SUM(CASE WHEN early_oral=1 AND late_insulin=1 THEN 1 ELSE 0 END) AS n_oral_to_insulin,
    SUM(CASE WHEN early_oral=1 AND late_oral=1 THEN 1 ELSE 0 END) AS n_oral_to_oral,
    SUM(CASE WHEN early_insulin=1 AND late_insulin=0 AND late_oral=0 THEN 1 ELSE 0 END) AS n_insulin_to_none,
    SUM(CASE WHEN early_oral=1 AND late_insulin=0 AND late_oral=0 THEN 1 ELSE 0 END) AS n_oral_to_none,
    SUM(CASE WHEN early_insulin=0 AND early_oral=0 AND (late_insulin=1 OR late_oral=1) THEN 1 ELSE 0 END) AS n_none_to_any
  FROM admission_exposure
)

SELECT
  n_admissions,
  n_early_insulin,
  ROUND(100.0 * n_early_insulin / n_admissions, 1) AS early_insulin_rate_pct,
  n_early_oral,
  ROUND(100.0 * n_early_oral / n_admissions, 1) AS early_oral_rate_pct,
  n_late_insulin,
  ROUND(100.0 * n_late_insulin / n_admissions, 1) AS late_insulin_rate_pct,
  n_late_oral,
  ROUND(100.0 * n_late_oral / n_admissions, 1) AS late_oral_rate_pct,
  -- Transitions
  n_insulin_to_insulin,
  ROUND(100.0 * n_insulin_to_insulin / n_admissions, 1) AS insulin_to_insulin_pct,
  n_insulin_to_oral,
  ROUND(100.0 * n_insulin_to_oral / n_admissions, 1) AS insulin_to_oral_pct,
  n_oral_to_insulin,
  ROUND(100.0 * n_oral_to_insulin / n_admissions, 1) AS oral_to_insulin_pct,
  n_oral_to_oral,
  ROUND(100.0 * n_oral_to_oral / n_admissions, 1) AS oral_to_oral_pct,
  n_insulin_to_none,
  ROUND(100.0 * n_insulin_to_none / n_admissions, 1) AS insulin_to_none_pct,
  n_oral_to_none,
  ROUND(100.0 * n_oral_to_none / n_admissions, 1) AS oral_to_none_pct,
  n_none_to_any,
  ROUND(100.0 * n_none_to_any / n_admissions, 1) AS none_to_any_pct
FROM summary;