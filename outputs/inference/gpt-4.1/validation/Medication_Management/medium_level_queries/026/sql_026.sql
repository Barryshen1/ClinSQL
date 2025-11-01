WITH
-- 1. Identify T2D and HF ICD codes
t2d_icds AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- ICD-10 E11.x
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E11'))
    -- ICD-9 250.x0, 250.x2 (exclude type 1)
    OR (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250[0-9][02]'))
),
hf_icds AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- ICD-10 I50.x
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I50'))
    -- ICD-9 428.x
    OR (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^428'))
),
-- 2. Admissions with both T2D and HF
admissions_with_t2d_hf AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- Age and gender filter
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
      INNER JOIN t2d_icds t2d
        ON d1.icd_code = t2d.icd_code AND d1.icd_version = t2d.icd_version
      WHERE d1.subject_id = a.subject_id AND d1.hadm_id = a.hadm_id
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      INNER JOIN hf_icds hf
        ON d2.icd_code = hf.icd_code AND d2.icd_version = hf.icd_version
      WHERE d2.subject_id = a.subject_id AND d2.hadm_id = a.hadm_id
    )
),
-- 3. Drug lists
oral_agents AS (
  SELECT DISTINCT LOWER(drug) AS drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    -- Common oral T2D drugs
    REGEXP_CONTAINS(LOWER(drug), r'metformin|glipizide|glyburide|glimepiride|pioglitazone|rosiglitazone|sitagliptin|linagliptin|canagliflozin|dapagliflozin|empagliflozin|repaglinide|nateglinide|acarbose|miglitol')
),
-- 4. First prescription times for insulin and oral agents per admission
first_drug_orders AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- First insulin order time
    MIN(CASE WHEN REGEXP_CONTAINS(LOWER(pr.drug), r'insulin') THEN pr.starttime END) AS first_insulin_time,
    -- First oral agent order time
    MIN(CASE WHEN LOWER(pr.drug) IN (SELECT drug FROM oral_agents) THEN pr.starttime END) AS first_oral_time
  FROM admissions_with_t2d_hf a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON a.subject_id = pr.subject_id AND a.hadm_id = pr.hadm_id
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime
),
-- 5. Initiation flags for each window
initiation_flags AS (
  SELECT
    subject_id,
    hadm_id,
    -- Insulin initiation in first 72h
    CASE
      WHEN first_insulin_time IS NOT NULL AND TIMESTAMP_DIFF(first_insulin_time, admittime, HOUR) BETWEEN 0 AND 72
      THEN 1 ELSE 0 END AS insulin_first72h,
    -- Oral agent initiation in first 72h
    CASE
      WHEN first_oral_time IS NOT NULL AND TIMESTAMP_DIFF(first_oral_time, admittime, HOUR) BETWEEN 0 AND 72
      THEN 1 ELSE 0 END AS oral_first72h,
    -- Insulin initiation in final 72h
    CASE
      WHEN first_insulin_time IS NOT NULL AND TIMESTAMP_DIFF(dischtime, first_insulin_time, HOUR) BETWEEN 0 AND 72
      THEN 1 ELSE 0 END AS insulin_final72h,
    -- Oral agent initiation in final 72h
    CASE
      WHEN first_oral_time IS NOT NULL AND TIMESTAMP_DIFF(dischtime, first_oral_time, HOUR) BETWEEN 0 AND 72
      THEN 1 ELSE 0 END AS oral_final72h
  FROM first_drug_orders
)
-- 6. Aggregate percentages
SELECT
  COUNT(*) AS n_admissions,
  ROUND(100 * SUM(insulin_first72h) / COUNT(*), 1) AS pct_insulin_first72h,
  ROUND(100 * SUM(oral_first72h) / COUNT(*), 1) AS pct_oral_first72h,
  ROUND(100 * SUM(insulin_final72h) / COUNT(*), 1) AS pct_insulin_final72h,
  ROUND(100 * SUM(oral_final72h) / COUNT(*), 1) AS pct_oral_final72h
FROM initiation_flags;