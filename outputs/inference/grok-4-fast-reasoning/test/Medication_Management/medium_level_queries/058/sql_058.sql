WITH cohort AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
  GROUP BY a.hadm_id
  HAVING COUNT(CASE WHEN ((d.icd_version = 10 AND d.icd_code LIKE 'E11%') OR (d.icd_version = 9 AND d.icd_code LIKE '250%')) THEN 1 END) > 0
     AND COUNT(CASE WHEN ((d.icd_version = 10 AND d.icd_code LIKE 'I50%') OR (d.icd_version = 9 AND d.icd_code LIKE '428%')) THEN 1 END) > 0
),
total_n AS (
  SELECT COUNT(*) AS n FROM cohort
),
init_times AS (
  SELECT 
    classified.hadm_id,
    classified.antidiabetic_class AS class,
    MIN(classified.starttime) AS first_start
  FROM (
    SELECT 
      hadm_id,
      starttime,
      drug,
      CASE
        WHEN LOWER(drug) LIKE '%insulin%' THEN 'Insulin'
        WHEN LOWER(drug) LIKE '%metformin%' THEN 'Metformin'
        WHEN LOWER(drug) LIKE '%glipizide%' OR 
             LOWER(drug) LIKE '%glyburide%' OR 
             LOWER(drug) LIKE '%glimepiride%' OR 
             LOWER(drug) LIKE '%tolbutamide%' OR 
             LOWER(drug) LIKE '%chlorpropamide%' THEN 'Sulfonylurea'
        WHEN LOWER(drug) LIKE '%pioglitazone%' OR 
             LOWER(drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinedione'
        WHEN LOWER(drug) LIKE '%sitagliptin%' OR 
             LOWER(drug) LIKE '%saxagliptin%' OR 
             LOWER(drug) LIKE '%linagliptin%' OR 
             LOWER(drug) LIKE '%alogliptin%' THEN 'DPP-4 Inhibitor'
        WHEN LOWER(drug) LIKE '%canagliflozin%' OR 
             LOWER(drug) LIKE '%dapagliflozin%' OR 
             LOWER(drug) LIKE '%empagliflozin%' OR 
             LOWER(drug) LIKE '%ertugliflozin%' THEN 'SGLT2 Inhibitor'
        WHEN LOWER(drug) LIKE '%exenatide%' OR 
             LOWER(drug) LIKE '%liraglutide%' OR 
             LOWER(drug) LIKE '%dulaglutide%' OR 
             LOWER(drug) LIKE '%semaglutide%' THEN 'GLP-1 Agonist'
        ELSE NULL
      END AS antidiabetic_class
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE drug IS NOT NULL
      AND starttime IS NOT NULL
  ) classified
  JOIN cohort c ON classified.hadm_id = c.hadm_id
  WHERE classified.antidiabetic_class IS NOT NULL
  GROUP BY classified.hadm_id, classified.antidiabetic_class
),
first12 AS (
  SELECT 
    it.class,
    COUNT(DISTINCT it.hadm_id) AS n
  FROM init_times it
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON it.hadm_id = a.hadm_id
  WHERE it.first_start >= a.admittime
    AND it.first_start < TIMESTAMP_ADD(a.admittime, INTERVAL 12 HOUR)
  GROUP BY it.class
),
last48 AS (
  SELECT 
    it.class,
    COUNT(DISTINCT it.hadm_id) AS n
  FROM init_times it
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON it.hadm_id = a.hadm_id
  WHERE it.first_start >= TIMESTAMP_SUB(a.dischtime, INTERVAL 48 HOUR)
    AND it.first_start < a.dischtime
  GROUP BY it.class
)
SELECT 
  COALESCE(f.class, l.class) AS antidiabetic_class,
  ROUND(COALESCE(f.n, 0) * 1.0 / tn.n * 100, 2) AS first12_rate_pct,
  ROUND(COALESCE(l.n, 0) * 1.0 / tn.n * 100, 2) AS last48_rate_pct,
  ROUND((COALESCE(l.n, 0) - COALESCE(f.n, 0)) * 1.0 / tn.n * 100, 2) AS net_change_pp
FROM first12 f
FULL OUTER JOIN last48 l ON f.class = l.class
CROSS JOIN total_n tn
ORDER BY antidiabetic_class;