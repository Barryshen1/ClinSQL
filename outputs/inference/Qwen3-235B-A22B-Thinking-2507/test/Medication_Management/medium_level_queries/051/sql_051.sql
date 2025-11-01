WITH 
-- Step 1: Define the cohort of patients
cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 86 AND 96
    -- Filter for DM (Diabetes Mellitus)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND (
          d.icd_code LIKE 'E08%' OR
          d.icd_code LIKE 'E09%' OR
          d.icd_code LIKE 'E10%' OR
          d.icd_code LIKE 'E11%' OR
          d.icd_code LIKE 'E12%' OR
          d.icd_code LIKE 'E13%'
        )
    )
    -- Filter for HF (Heart Failure)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'I50%'
    )
),

-- Step 2: Determine drug usage in early and late periods
drug_usage AS (
  SELECT
    c.hadm_id,
    -- Early period (first 12 hours)
    MAX(CASE 
          WHEN p.starttime < DATETIME_ADD(c.admittime, INTERVAL 12 HOUR) 
            AND (p.stoptime IS NULL OR p.stoptime > c.admittime)
            AND LOWER(p.drug) LIKE '%insulin%' 
          THEN 1 ELSE 0 
        END) AS has_insulin_early,
    MAX(CASE 
          WHEN p.starttime < DATETIME_ADD(c.admittime, INTERVAL 12 HOUR) 
            AND (p.stoptime IS NULL OR p.stoptime > c.admittime)
            AND (
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
              LOWER(p.drug) LIKE '%acarbose%' OR
              LOWER(p.drug) LIKE '%miglitol%' OR
              LOWER(p.drug) LIKE '%repaglinide%' OR
              LOWER(p.drug) LIKE '%nateglinide%'
            )
          THEN 1 ELSE 0 
        END) AS has_oral_early,
    -- Late period (final 72 hours)
    MAX(CASE 
          WHEN p.starttime < c.dischtime 
            AND (p.stoptime IS NULL OR p.stoptime > DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR))
            AND LOWER(p.drug) LIKE '%insulin%' 
          THEN 1 ELSE 0 
        END) AS has_insulin_late,
    MAX(CASE 
          WHEN p.starttime < c.dischtime 
            AND (p.stoptime IS NULL OR p.stoptime > DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR))
            AND (
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
              LOWER(p.drug) LIKE '%acarbose%' OR
              LOWER(p.drug) LIKE '%miglitol%' OR
              LOWER(p.drug) LIKE '%repaglinide%' OR
              LOWER(p.drug) LIKE '%nateglinide%'
            )
          THEN 1 ELSE 0 
        END) AS has_oral_late
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  GROUP BY c.hadm_id
),

-- Step 3: Calculate rates and transitions
rates AS (
  SELECT
    'early' AS period,
    'Insulin' AS class,
    SUM(has_insulin_early) * 100.0 / COUNT(*) AS rate
  FROM drug_usage
  UNION ALL
  SELECT
    'early' AS period,
    'Oral Agents' AS class,
    SUM(has_oral_early) * 100.0 / COUNT(*) AS rate
  FROM drug_usage
  UNION ALL
  SELECT
    'late' AS period,
    'Insulin' AS class,
    SUM(has_insulin_late) * 100.0 / COUNT(*) AS rate
  FROM drug_usage
  UNION ALL
  SELECT
    'late' AS period,
    'Oral Agents' AS class,
    SUM(has_oral_late) * 100.0 / COUNT(*) AS rate
  FROM drug_usage
),

transitions AS (
  SELECT
    CASE 
      WHEN has_insulin_early = 1 AND has_oral_early = 1 THEN 'Both'
      WHEN has_insulin_early = 1 THEN 'Insulin'
      WHEN has_oral_early = 1 THEN 'Oral'
      ELSE 'None'
    END AS early_state,
    CASE 
      WHEN has_insulin_late = 1 AND has_oral_late = 1 THEN 'Both'
      WHEN has_insulin_late = 1 THEN 'Insulin'
      WHEN has_oral_late = 1 THEN 'Oral'
      ELSE 'None'
    END AS late_state,
    COUNT(*) AS transition_count
  FROM drug_usage
  GROUP BY early_state, late_state
)

-- Final result combining rates and transitions
SELECT
  'rate' AS metric_type,
  period,
  class,
  rate,
  NULL AS early_state,
  NULL AS late_state,
  NULL AS transition_count
FROM rates
UNION ALL
SELECT
  'transition' AS metric_type,
  NULL AS period,
  NULL AS class,
  NULL AS rate,
  early_state,
  late_state,
  transition_count
FROM transitions
ORDER BY metric_type, period, class, early_state, late_state;