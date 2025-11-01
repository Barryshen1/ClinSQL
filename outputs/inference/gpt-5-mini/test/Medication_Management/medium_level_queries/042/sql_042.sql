WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND a.dischtime IS NOT NULL
    -- has a diabetes diagnosis in this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes%'
    )
    -- has an acute heart failure diagnosis in this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%heart failure%'
        AND LOWER(dd.long_title) LIKE '%acute%'
    )
),

-- For each admission, compute flags for insulin/oral presence in windows
med_flags AS (
  SELECT
    c.hadm_id,
    -- 0/1 flags for insulin in first 48h / final 24h
    MAX(CASE
          WHEN pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
           AND LOWER(pr.drug) LIKE '%insulin%' THEN 1
          ELSE 0
        END) AS insulin_first48_flag,
    MAX(CASE
          WHEN pr.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
           AND LOWER(pr.drug) LIKE '%insulin%' THEN 1
          ELSE 0
        END) AS insulin_final24_flag,
    -- 0/1 flags for oral antihyperglycemic agents in first 48h / final 24h
    MAX(CASE
          WHEN pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
           AND (
             LOWER(pr.drug) LIKE '%metformin%' OR
             LOWER(pr.drug) LIKE '%glipizide%' OR
             LOWER(pr.drug) LIKE '%glyburide%' OR
             LOWER(pr.drug) LIKE '%glimepiride%' OR
             LOWER(pr.drug) LIKE '%sitagliptin%' OR
             LOWER(pr.drug) LIKE '%linagliptin%' OR
             LOWER(pr.drug) LIKE '%saxagliptin%' OR
             LOWER(pr.drug) LIKE '%empagliflozin%' OR
             LOWER(pr.drug) LIKE '%canagliflozin%' OR
             LOWER(pr.drug) LIKE '%dapagliflozin%' OR
             LOWER(pr.drug) LIKE '%pioglitazone%' OR
             LOWER(pr.drug) LIKE '%rosiglitazone%' OR
             LOWER(pr.drug) LIKE '%acarbose%' OR
             LOWER(pr.drug) LIKE '%miglitol%' OR
             LOWER(pr.drug) LIKE '%repaglinide%' OR
             LOWER(pr.drug) LIKE '%nateglinide%' OR
             LOWER(pr.drug) LIKE '%gliclazide%'
           ) THEN 1
          ELSE 0
        END) AS oral_first48_flag,
    MAX(CASE
          WHEN pr.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
           AND (
             LOWER(pr.drug) LIKE '%metformin%' OR
             LOWER(pr.drug) LIKE '%glipizide%' OR
             LOWER(pr.drug) LIKE '%glyburide%' OR
             LOWER(pr.drug) LIKE '%glimepiride%' OR
             LOWER(pr.drug) LIKE '%sitagliptin%' OR
             LOWER(pr.drug) LIKE '%linagliptin%' OR
             LOWER(pr.drug) LIKE '%saxagliptin%' OR
             LOWER(pr.drug) LIKE '%empagliflozin%' OR
             LOWER(pr.drug) LIKE '%canagliflozin%' OR
             LOWER(pr.drug) LIKE '%dapagliflozin%' OR
             LOWER(pr.drug) LIKE '%pioglitazone%' OR
             LOWER(pr.drug) LIKE '%rosiglitazone%' OR
             LOWER(pr.drug) LIKE '%acarbose%' OR
             LOWER(pr.drug) LIKE '%miglitol%' OR
             LOWER(pr.drug) LIKE '%repaglinide%' OR
             LOWER(pr.drug) LIKE '%nateglinide%' OR
             LOWER(pr.drug) LIKE '%gliclazide%'
           ) THEN 1
          ELSE 0
        END) AS oral_final24_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.hadm_id = c.hadm_id
  GROUP BY c.hadm_id
),

-- Aggregate counts and compute continued/initiated/discontinued
metrics AS (
  SELECT
    COUNT(*) AS total_admissions,
    SUM(insulin_first48_flag) AS insulin_first48_count,
    SUM(insulin_final24_flag) AS insulin_final24_count,
    SUM(CASE WHEN insulin_first48_flag = 1 AND insulin_final24_flag = 1 THEN 1 ELSE 0 END) AS insulin_continued_count,
    SUM(CASE WHEN insulin_first48_flag = 0 AND insulin_final24_flag = 1 THEN 1 ELSE 0 END) AS insulin_initiated_count,
    SUM(CASE WHEN insulin_first48_flag = 1 AND insulin_final24_flag = 0 THEN 1 ELSE 0 END) AS insulin_discontinued_count,
    SUM(oral_first48_flag) AS oral_first48_count,
    SUM(oral_final24_flag) AS oral_final24_count,
    SUM(CASE WHEN oral_first48_flag = 1 AND oral_final24_flag = 1 THEN 1 ELSE 0 END) AS oral_continued_count,
    SUM(CASE WHEN oral_first48_flag = 0 AND oral_final24_flag = 1 THEN 1 ELSE 0 END) AS oral_initiated_count,
    SUM(CASE WHEN oral_first48_flag = 1 AND oral_final24_flag = 0 THEN 1 ELSE 0 END) AS oral_discontinued_count
  FROM med_flags
)

-- Final reporting: counts and percents
SELECT
  total_admissions,
  insulin_first48_count,
  ROUND(100.0 * SAFE_DIVIDE(insulin_first48_count, total_admissions), 2) AS insulin_first48_percent,
  insulin_final24_count,
  ROUND(100.0 * SAFE_DIVIDE(insulin_final24_count, total_admissions), 2) AS insulin_final24_percent,
  insulin_continued_count,
  insulin_initiated_count,
  insulin_discontinued_count,
  oral_first48_count,
  ROUND(100.0 * SAFE_DIVIDE(oral_first48_count, total_admissions), 2) AS oral_first48_percent,
  oral_final24_count,
  ROUND(100.0 * SAFE_DIVIDE(oral_final24_count, total_admissions), 2) AS oral_final24_percent,
  oral_continued_count,
  oral_initiated_count,
  oral_discontinued_count
FROM metrics;