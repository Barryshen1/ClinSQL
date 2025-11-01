WITH
-- 1. Get cohort: female, age 51-61, diabetes AND acute HF
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  -- Age and gender filter
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d1
      WHERE d1.hadm_id = a.hadm_id
        AND (
          -- Diabetes ICD-10 E08-E13 or ICD-9 250
          (d1.icd_version = 10 AND (
            LEFT(d1.icd_code, 3) BETWEEN 'E08' AND 'E13'
          ))
          OR (d1.icd_version = 9 AND LEFT(d1.icd_code, 3) = '250')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d2
      WHERE d2.hadm_id = a.hadm_id
        AND (
          -- Acute HF ICD-10 I50.x or ICD-9 428
          (d2.icd_version = 10 AND LEFT(d2.icd_code, 3) = 'I50')
          OR (d2.icd_version = 9 AND LEFT(d2.icd_code, 3) = '428')
        )
    )
),

-- 2. Medication administrations in first 48h and final 24h
med_admin AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    e.charttime,
    LOWER(e.medication) AS med_name,
    CASE
      WHEN LOWER(e.medication) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(e.medication) LIKE '%metformin%' THEN 'oral'
      WHEN LOWER(e.medication) LIKE '%glyburide%' THEN 'oral'
      WHEN LOWER(e.medication) LIKE '%glipizide%' THEN 'oral'
      WHEN LOWER(e.medication) LIKE '%glimepiride%' THEN 'oral'
      WHEN LOWER(e.medication) LIKE '%sitagliptin%' THEN 'oral'
      WHEN LOWER(e.medication) LIKE '%pioglitazone%' THEN 'oral'
      WHEN LOWER(e.medication) LIKE '%repaglinide%' THEN 'oral'
      WHEN LOWER(e.medication) LIKE '%nateglinide%' THEN 'oral'
      WHEN LOWER(e.medication) LIKE '%canagliflozin%' THEN 'oral'
      WHEN LOWER(e.medication) LIKE '%dapagliflozin%' THEN 'oral'
      WHEN LOWER(e.medication) LIKE '%empagliflozin%' THEN 'oral'
      WHEN LOWER(e.medication) LIKE '%linagliptin%' THEN 'oral'
      WHEN LOWER(e.medication) LIKE '%alogliptin%' THEN 'oral'
      WHEN LOWER(e.medication) LIKE '%rosiglitazone%' THEN 'oral'
      ELSE NULL
    END AS agent_type,
    CASE
      WHEN e.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR) THEN 'first48h'
      WHEN e.charttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime THEN 'final24h'
      ELSE NULL
    END AS time_window
  FROM cohort c
  JOIN physionet-data.mimiciv_3_1_hosp.emar e
    ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
  WHERE (
    LOWER(e.medication) LIKE '%insulin%'
    OR LOWER(e.medication) LIKE '%metformin%'
    OR LOWER(e.medication) LIKE '%glyburide%'
    OR LOWER(e.medication) LIKE '%glipizide%'
    OR LOWER(e.medication) LIKE '%glimepiride%'
    OR LOWER(e.medication) LIKE '%sitagliptin%'
    OR LOWER(e.medication) LIKE '%pioglitazone%'
    OR LOWER(e.medication) LIKE '%repaglinide%'
    OR LOWER(e.medication) LIKE '%nateglinide%'
    OR LOWER(e.medication) LIKE '%canagliflozin%'
    OR LOWER(e.medication) LIKE '%dapagliflozin%'
    OR LOWER(e.medication) LIKE '%empagliflozin%'
    OR LOWER(e.medication) LIKE '%linagliptin%'
    OR LOWER(e.medication) LIKE '%alogliptin%'
    OR LOWER(e.medication) LIKE '%rosiglitazone%'
  )
),

-- 3. Fallback: prescriptions if no EMAR record
presc_admin AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    p.starttime,
    p.stoptime,
    LOWER(p.drug) AS med_name,
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'oral'
      WHEN LOWER(p.drug) LIKE '%glyburide%' THEN 'oral'
      WHEN LOWER(p.drug) LIKE '%glipizide%' THEN 'oral'
      WHEN LOWER(p.drug) LIKE '%glimepiride%' THEN 'oral'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' THEN 'oral'
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' THEN 'oral'
      WHEN LOWER(p.drug) LIKE '%repaglinide%' THEN 'oral'
      WHEN LOWER(p.drug) LIKE '%nateglinide%' THEN 'oral'
      WHEN LOWER(p.drug) LIKE '%canagliflozin%' THEN 'oral'
      WHEN LOWER(p.drug) LIKE '%dapagliflozin%' THEN 'oral'
      WHEN LOWER(p.drug) LIKE '%empagliflozin%' THEN 'oral'
      WHEN LOWER(p.drug) LIKE '%linagliptin%' THEN 'oral'
      WHEN LOWER(p.drug) LIKE '%alogliptin%' THEN 'oral'
      WHEN LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'oral'
      ELSE NULL
    END AS agent_type,
    CASE
      WHEN p.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
           AND p.stoptime >= c.admittime THEN 'first48h'
      WHEN p.starttime <= c.dischtime
           AND p.stoptime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) THEN 'final24h'
      ELSE NULL
    END AS time_window
  FROM cohort c
  JOIN physionet-data.mimiciv_3_1_hosp.prescriptions p
    ON c.subject_id = p.subject_id AND c.hadm_id = p.hadm_id
  WHERE (
    LOWER(p.drug) LIKE '%insulin%'
    OR LOWER(p.drug) LIKE '%metformin%'
    OR LOWER(p.drug) LIKE '%glyburide%'
    OR LOWER(p.drug) LIKE '%glipizide%'
    OR LOWER(p.drug) LIKE '%glimepiride%'
    OR LOWER(p.drug) LIKE '%sitagliptin%'
    OR LOWER(p.drug) LIKE '%pioglitazone%'
    OR LOWER(p.drug) LIKE '%repaglinide%'
    OR LOWER(p.drug) LIKE '%nateglinide%'
    OR LOWER(p.drug) LIKE '%canagliflozin%'
    OR LOWER(p.drug) LIKE '%dapagliflozin%'
    OR LOWER(p.drug) LIKE '%empagliflozin%'
    OR LOWER(p.drug) LIKE '%linagliptin%'
    OR LOWER(p.drug) LIKE '%alogliptin%'
    OR LOWER(p.drug) LIKE '%rosiglitazone%'
  )
),

-- 4. Union EMAR and prescriptions, deduplicate by hadm_id, agent_type, time_window
all_admin AS (
  SELECT subject_id, hadm_id, agent_type, time_window
  FROM med_admin
  WHERE agent_type IS NOT NULL AND time_window IS NOT NULL
  UNION DISTINCT
  SELECT subject_id, hadm_id, agent_type, time_window
  FROM presc_admin
  WHERE agent_type IS NOT NULL AND time_window IS NOT NULL
),

-- 5. For each admission, flag insulin/oral in each window
adm_summary AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN a.agent_type = 'insulin' AND a.time_window = 'first48h' THEN 1 ELSE 0 END) AS insulin_first48h,
    MAX(CASE WHEN a.agent_type = 'insulin' AND a.time_window = 'final24h' THEN 1 ELSE 0 END) AS insulin_final24h,
    MAX(CASE WHEN a.agent_type = 'oral' AND a.time_window = 'first48h' THEN 1 ELSE 0 END) AS oral_first48h,
    MAX(CASE WHEN a.agent_type = 'oral' AND a.time_window = 'final24h' THEN 1 ELSE 0 END) AS oral_final24h
  FROM cohort c
  LEFT JOIN all_admin a
    ON c.subject_id = a.subject_id AND c.hadm_id = a.hadm_id
  GROUP BY c.subject_id, c.hadm_id
),

-- 6. Aggregate counts for continued/initiated/discontinued
agent_counts AS (
  SELECT
    -- Insulin
    SUM(CASE WHEN insulin_first48h = 1 AND insulin_final24h = 1 THEN 1 ELSE 0 END) AS insulin_continued,
    SUM(CASE WHEN insulin_first48h = 0 AND insulin_final24h = 1 THEN 1 ELSE 0 END) AS insulin_initiated,
    SUM(CASE WHEN insulin_first48h = 1 AND insulin_final24h = 0 THEN 1 ELSE 0 END) AS insulin_discontinued,
    -- Oral
    SUM(CASE WHEN oral_first48h = 1 AND oral_final24h = 1 THEN 1 ELSE 0 END) AS oral_continued,
    SUM(CASE WHEN oral_first48h = 0 AND oral_final24h = 1 THEN 1 ELSE 0 END) AS oral_initiated,
    SUM(CASE WHEN oral_first48h = 1 AND oral_final24h = 0 THEN 1 ELSE 0 END) AS oral_discontinued,
    -- Denominator
    COUNT(*) AS n_admissions,
    -- Percent on agent in each window
    SUM(CASE WHEN insulin_first48h = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS pct_insulin_first48h,
    SUM(CASE WHEN insulin_final24h = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS pct_insulin_final24h,
    SUM(CASE WHEN oral_first48h = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS pct_oral_first48h,
    SUM(CASE WHEN oral_final24h = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS pct_oral_final24h
  FROM adm_summary
)

SELECT
  n_admissions,
  pct_insulin_first48h,
  pct_insulin_final24h,
  pct_oral_first48h,
  pct_oral_final24h,
  insulin_continued,
  insulin_initiated,
  insulin_discontinued,
  oral_continued,
  oral_initiated,
  oral_discontinued
FROM agent_counts
;