WITH patients_age_gender AS (
  SELECT 
    subject_id,
    anchor_age,
    anchor_year,
    gender
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'F'
),
admissions_with_age AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_age_gender p
    ON a.subject_id = p.subject_id
  WHERE p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 51 AND 61
),
diabetes_hf_diagnoses AS (
  SELECT 
    di.hadm_id,
    MAX(CASE WHEN di.icd_code LIKE 'E1%' AND di.icd_version = 10 THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN di.icd_code LIKE 'I50%' AND di.icd_version = 10 THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  GROUP BY di.hadm_id
),
cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM admissions_with_age a
  INNER JOIN diabetes_hf_diagnoses d
    ON a.hadm_id = d.hadm_id
  WHERE d.has_diabetes = 1 AND d.has_hf = 1
),
prescriptions_classified AS (
  SELECT 
    p.hadm_id,
    p.starttime,
    p.stoptime,
    CASE 
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(p.drug) IN (
        'metformin', 'glipizide', 'glyburide', 'glimepiride', 'sitagliptin', 'saxagliptin',
        'linagliptin', 'alogliptin', 'empagliflozin', 'dapagliflozin', 'canagliflozin',
        'pioglitazone', 'rosiglitazone', 'acarbose', 'miglitol', 'repaglinide', 'nateglinide'
      ) OR LOWER(p.drug) LIKE '%metformin%' 
        OR LOWER(p.drug) LIKE '%gli%' 
        OR LOWER(p.drug) LIKE '%gliptin%' 
        OR LOWER(p.drug) LIKE '%gliflozin%' 
        OR LOWER(p.drug) LIKE '%glitazone%' 
        OR LOWER(p.drug) LIKE '%repaglinide%' 
        OR LOWER(p.drug) LIKE '%acarbose%'
      THEN 'oral'
      ELSE 'other'
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  INNER JOIN cohort c
    ON p.hadm_id = c.hadm_id
  WHERE p.starttime IS NOT NULL
),
drug_exposure AS (
  SELECT 
    c.hadm_id,
    -- Insulin in first 48h
    MAX(CASE WHEN pc.drug_class = 'insulin' 
              AND pc.starttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
              AND (pc.stoptime IS NULL OR pc.stoptime >= c.admittime)
         THEN 1 ELSE 0 END) AS insulin_first48,
    -- Insulin in final 24h
    MAX(CASE WHEN pc.drug_class = 'insulin' 
              AND pc.starttime <= c.dischtime
              AND (pc.stoptime IS NULL OR pc.stoptime >= DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR))
         THEN 1 ELSE 0 END) AS insulin_last24,
    -- Oral agents in first 48h
    MAX(CASE WHEN pc.drug_class = 'oral' 
              AND pc.starttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
              AND (pc.stoptime IS NULL OR pc.stoptime >= c.admittime)
         THEN 1 ELSE 0 END) AS oral_first48,
    -- Oral agents in final 24h
    MAX(CASE WHEN pc.drug_class = 'oral' 
              AND pc.starttime <= c.dischtime
              AND (pc.stoptime IS NULL OR pc.stoptime >= DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR))
         THEN 1 ELSE 0 END) AS oral_last24
  FROM cohort c
  LEFT JOIN prescriptions_classified pc
    ON c.hadm_id = pc.hadm_id
  GROUP BY c.hadm_id
),
summary_stats AS (
  SELECT 
    COUNT(*) AS total_patients,
    AVG(insulin_first48) AS pct_insulin_first48,
    AVG(insulin_last24) AS pct_insulin_last24,
    AVG(oral_first48) AS pct_oral_first48,
    AVG(oral_last24) AS pct_oral_last24,
    SUM(CASE WHEN insulin_first48 = 1 AND insulin_last24 = 1 THEN 1 ELSE 0 END) AS insulin_continued,
    SUM(CASE WHEN insulin_first48 = 0 AND insulin_last24 = 1 THEN 1 ELSE 0 END) AS insulin_initiated,
    SUM(CASE WHEN insulin_first48 = 1 AND insulin_last24 = 0 THEN 1 ELSE 0 END) AS insulin_discontinued,
    SUM(CASE WHEN oral_first48 = 1 AND oral_last24 = 1 THEN 1 ELSE 0 END) AS oral_continued,
    SUM(CASE WHEN oral_first48 = 0 AND oral_last24 = 1 THEN 1 ELSE 0 END) AS oral_initiated,
    SUM(CASE WHEN oral_first48 = 1 AND oral_last24 = 0 THEN 1 ELSE 0 END) AS oral_discontinued
  FROM drug_exposure
)
-- Final result: combine percentages and counts in one result set
SELECT 
  'percentage' AS metric_type,
  time_window,
  drug_class,
  ROUND(100 * value, 2) AS value,
  NULL AS count_val
FROM (
  SELECT 'first_48h' AS time_window, 'insulin' AS drug_class, pct_insulin_first48 AS value FROM summary_stats
  UNION ALL
  SELECT 'first_48h', 'oral', pct_oral_first48 FROM summary_stats
  UNION ALL
  SELECT 'final_24h', 'insulin', pct_insulin_last24 FROM summary_stats
  UNION ALL
  SELECT 'final_24h', 'oral', pct_oral_last24 FROM summary_stats
)
UNION ALL
SELECT 
  'count' AS metric_type,
  status AS time_window,
  drug_class,
  NULL AS value,
  count_val
FROM (
  SELECT 'continued' AS status, 'insulin' AS drug_class, insulin_continued AS count_val FROM summary_stats
  UNION ALL
  SELECT 'initiated', 'insulin', insulin_initiated FROM summary_stats
  UNION ALL
  SELECT 'discontinued', 'insulin', insulin_discontinued FROM summary_stats
  UNION ALL
  SELECT 'continued', 'oral', oral_continued FROM summary_stats
  UNION ALL
  SELECT 'initiated', 'oral', oral_initiated FROM summary_stats
  UNION ALL
  SELECT 'discontinued', 'oral', oral_discontinued FROM summary_stats
);