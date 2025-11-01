WITH
-- 1. Identify female patients age 44-54
female_44_54 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 44 AND 54
),

-- 2. Identify admissions with T2DM and HF
t2dm_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    -- ICD-10 T2DM
    (icd_version = 10 AND (icd_code LIKE 'E11%' ))
    -- ICD-9 T2DM
    OR (icd_version = 9 AND (
      icd_code LIKE '250.0%' OR icd_code LIKE '250.2%' OR icd_code LIKE '250.4%' OR
      icd_code LIKE '250.6%' OR icd_code LIKE '250.8%' OR icd_code LIKE '250.9%'
    ))
  )
),
hf_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    -- ICD-10 HF
    (icd_version = 10 AND (icd_code LIKE 'I50%' ))
    -- ICD-9 HF
    OR (icd_version = 9 AND (icd_code LIKE '428%' ))
  )
),
-- Admissions with both T2DM and HF
cohort_hadm AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN female_44_54 p ON a.subject_id = p.subject_id
  JOIN t2dm_hadm t ON a.hadm_id = t.hadm_id
  JOIN hf_hadm h ON a.hadm_id = h.hadm_id
  WHERE TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48 -- Only admissions >=48h
),

-- 3. Medication exposure windows
-- Insulin and oral agent definitions
insulin_drugs AS (
  SELECT DISTINCT LOWER(drug) AS drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%insulin%'
),
oral_drugs AS (
  SELECT DISTINCT LOWER(drug) AS drug
  FROM UNNEST([
    'metformin', 'glipizide', 'glyburide', 'glimepiride', 'pioglitazone',
    'rosiglitazone', 'sitagliptin', 'linagliptin', 'canagliflozin', 'dapagliflozin',
    'empagliflozin', 'repaglinide', 'nateglinide', 'acarbose', 'miglitol'
  ]) AS drug
),

-- Get medication exposures in first 24h and last 48h
med_exposure AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    -- Insulin exposure
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%insulin%' AND pr.starttime >= c.admittime AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END) AS insulin_first24h,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%insulin%' AND pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND pr.starttime < c.dischtime THEN 1 ELSE 0 END) AS insulin_last48h,
    -- Oral agent exposure
    MAX(CASE WHEN (
      LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR
      LOWER(pr.drug) LIKE '%glimepiride%' OR LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%' OR
      LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%canagliflozin%' OR
      LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%repaglinide%' OR
      LOWER(pr.drug) LIKE '%nateglinide%' OR LOWER(pr.drug) LIKE '%acarbose%' OR LOWER(pr.drug) LIKE '%miglitol%'
    ) AND pr.starttime >= c.admittime AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END) AS oral_first24h,
    MAX(CASE WHEN (
      LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR
      LOWER(pr.drug) LIKE '%glimepiride%' OR LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%' OR
      LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%canagliflozin%' OR
      LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%repaglinide%' OR
      LOWER(pr.drug) LIKE '%nateglinide%' OR LOWER(pr.drug) LIKE '%acarbose%' OR LOWER(pr.drug) LIKE '%miglitol%'
    ) AND pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND pr.starttime < c.dischtime THEN 1 ELSE 0 END) AS oral_last48h
  FROM cohort_hadm c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
  GROUP BY c.subject_id, c.hadm_id
),

-- 4. Aggregate for prevalence and transitions
summary AS (
  SELECT
    COUNT(*) AS n_admissions,
    -- Insulin
    SUM(insulin_first24h) AS insulin_first24h_n,
    SUM(insulin_last48h) AS insulin_last48h_n,
    ROUND(SUM(insulin_first24h) * 100.0 / COUNT(*), 1) AS insulin_first24h_pct,
    ROUND(SUM(insulin_last48h) * 100.0 / COUNT(*), 1) AS insulin_last48h_pct,
    SUM(CASE WHEN insulin_first24h=1 AND insulin_last48h=1 THEN 1 ELSE 0 END) AS insulin_continued,
    SUM(CASE WHEN insulin_first24h=0 AND insulin_last48h=1 THEN 1 ELSE 0 END) AS insulin_initiated,
    SUM(CASE WHEN insulin_first24h=1 AND insulin_last48h=0 THEN 1 ELSE 0 END) AS insulin_discontinued,
    -- Oral agents
    SUM(oral_first24h) AS oral_first24h_n,
    SUM(oral_last48h) AS oral_last48h_n,
    ROUND(SUM(oral_first24h) * 100.0 / COUNT(*), 1) AS oral_first24h_pct,
    ROUND(SUM(oral_last48h) * 100.0 / COUNT(*), 1) AS oral_last48h_pct,
    SUM(CASE WHEN oral_first24h=1 AND oral_last48h=1 THEN 1 ELSE 0 END) AS oral_continued,
    SUM(CASE WHEN oral_first24h=0 AND oral_last48h=1 THEN 1 ELSE 0 END) AS oral_initiated,
    SUM(CASE WHEN oral_first24h=1 AND oral_last48h=0 THEN 1 ELSE 0 END) AS oral_discontinued
  FROM med_exposure
)

SELECT
  n_admissions,
  insulin_first24h_n, insulin_first24h_pct,
  insulin_last48h_n, insulin_last48h_pct,
  insulin_continued, insulin_initiated, insulin_discontinued,
  oral_first24h_n, oral_first24h_pct,
  oral_last48h_n, oral_last48h_pct,
  oral_continued, oral_initiated, oral_discontinued
FROM summary;