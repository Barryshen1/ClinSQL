WITH cohort AS (
  SELECT 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id 
    AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
  GROUP BY a.hadm_id, a.admittime, a.dischtime
  HAVING SUM(CASE 
    WHEN ((d.icd_version = 9 AND d.icd_code LIKE '250%' 
           AND d.icd_code NOT LIKE '2501%' AND d.icd_code NOT LIKE '2503%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'E11%')) 
    THEN 1 ELSE 0 
  END) > 0
  AND SUM(CASE 
    WHEN ((d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')) 
    THEN 1 ELSE 0 
  END) > 0
),
admins AS (
  SELECT 
    e.hadm_id, 
    e.charttime, 
    LOWER(ed.product_description) AS prod_desc
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed 
    ON e.subject_id = ed.subject_id 
    AND e.emar_id = ed.emar_id 
    AND e.emar_seq = ed.emar_seq
  WHERE ed.product_description IS NOT NULL
),
total_n AS (
  SELECT COUNT(*) AS n FROM cohort
)
SELECT 
  'First 72h' AS period,
  'Insulin' AS drug_class,
  COUNT(DISTINCT c.hadm_id) * 100.0 / (SELECT n FROM total_n) AS percent
FROM cohort c
WHERE EXISTS (
  SELECT 1 FROM admins a
  WHERE a.hadm_id = c.hadm_id
    AND a.charttime >= c.admittime
    AND a.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND a.prod_desc LIKE '%insulin%'
)
UNION ALL
SELECT 
  'First 72h' AS period,
  'Metformin' AS drug_class,
  COUNT(DISTINCT c.hadm_id) * 100.0 / (SELECT n FROM total_n) AS percent
FROM cohort c
WHERE EXISTS (
  SELECT 1 FROM admins a
  WHERE a.hadm_id = c.hadm_id
    AND a.charttime >= c.admittime
    AND a.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND a.prod_desc LIKE '%metformin%'
)
UNION ALL
SELECT 
  'First 72h' AS period,
  'Sulfonylurea' AS drug_class,
  COUNT(DISTINCT c.hadm_id) * 100.0 / (SELECT n FROM total_n) AS percent
FROM cohort c
WHERE EXISTS (
  SELECT 1 FROM admins a
  WHERE a.hadm_id = c.hadm_id
    AND a.charttime >= c.admittime
    AND a.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND (a.prod_desc LIKE '%glimepiride%' OR a.prod_desc LIKE '%glipizide%' 
         OR a.prod_desc LIKE '%glyburide%' OR a.prod_desc LIKE '%glibenclamide%' 
         OR a.prod_desc LIKE '%tolbutamide%' OR a.prod_desc LIKE '%chlorpropamide%')
)
UNION ALL
SELECT 
  'First 72h' AS period,
  'DPP-4' AS drug_class,
  COUNT(DISTINCT c.hadm_id) * 100.0 / (SELECT n FROM total_n) AS percent
FROM cohort c
WHERE EXISTS (
  SELECT 1 FROM admins a
  WHERE a.hadm_id = c.hadm_id
    AND a.charttime >= c.admittime
    AND a.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND (a.prod_desc LIKE '%sitagliptin%' OR a.prod_desc LIKE '%saxagliptin%' 
         OR a.prod_desc LIKE '%linagliptin%' OR a.prod_desc LIKE '%alogliptin%')
)
UNION ALL
SELECT 
  'First 72h' AS period,
  'SGLT2' AS drug_class,
  COUNT(DISTINCT c.hadm_id) * 100.0 / (SELECT n FROM total_n) AS percent
FROM cohort c
WHERE EXISTS (
  SELECT 1 FROM admins a
  WHERE a.hadm_id = c.hadm_id
    AND a.charttime >= c.admittime
    AND a.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND (a.prod_desc LIKE '%canagliflozin%' OR a.prod_desc LIKE '%dapagliflozin%' 
         OR a.prod_desc LIKE '%empagliflozin%' OR a.prod_desc LIKE '%ertugliflozin%')
)
UNION ALL
SELECT 
  'First 72h' AS period,
  'GLP-1' AS drug_class,
  COUNT(DISTINCT c.hadm_id) * 100.0 / (SELECT n FROM total_n) AS percent
FROM cohort c
WHERE EXISTS (
  SELECT 1 FROM admins a
  WHERE a.hadm_id = c.hadm_id
    AND a.charttime >= c.admittime
    AND a.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND (a.prod_desc LIKE '%exenatide%' OR a.prod_desc LIKE '%liraglutide%' 
         OR a.prod_desc LIKE '%dulaglutide%' OR a.prod_desc LIKE '%semaglutide%' 
         OR a.prod_desc LIKE '%albiglutide%' OR a.prod_desc LIKE '%lixisenatide%')
)
UNION ALL
SELECT 
  'First 72h' AS period,
  'TZD' AS drug_class,
  COUNT(DISTINCT c.hadm_id) * 100.0 / (SELECT n FROM total_n) AS percent
FROM cohort c
WHERE EXISTS (
  SELECT 1 FROM admins a
  WHERE a.hadm_id = c.hadm_id
    AND a.charttime >= c.admittime
    AND a.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND (a.prod_desc LIKE '%pioglitazone%' OR a.prod_desc LIKE '%rosiglitazone%')
)
UNION ALL
SELECT 
  'Last 72h' AS period,
  'Insulin' AS drug_class,
  COUNT(DISTINCT c.hadm_id) * 100.0 / (SELECT n FROM total_n) AS percent
FROM cohort c
WHERE EXISTS (
  SELECT 1 FROM admins a
  WHERE a.hadm_id = c.hadm_id
    AND a.charttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR)
    AND a.charttime < c.dischtime
    AND a.prod_desc LIKE '%insulin%'
)
UNION ALL
SELECT 
  'Last 72h' AS period,
  'Metformin' AS drug_class,
  COUNT(DISTINCT c.hadm_id) * 100.0 / (SELECT n FROM total_n) AS percent
FROM cohort c
WHERE EXISTS (
  SELECT 1 FROM admins a
  WHERE a.hadm_id = c.hadm_id
    AND a.charttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR)
    AND a.charttime < c.dischtime
    AND a.prod_desc LIKE '%metformin%'
)
UNION ALL
SELECT 
  'Last 72h' AS period,
  'Sulfonylurea' AS drug_class,
  COUNT(DISTINCT c.hadm_id) * 100.0 / (SELECT n FROM total_n) AS percent
FROM cohort c
WHERE EXISTS (
  SELECT 1 FROM admins a
  WHERE a.hadm_id = c.hadm_id
    AND a.charttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR)
    AND a.charttime < c.dischtime
    AND (a.prod_desc LIKE '%glimepiride%' OR a.prod_desc LIKE '%glipizide%' 
         OR a.prod_desc LIKE '%glyburide%' OR a.prod_desc LIKE '%glibenclamide%' 
         OR a.prod_desc LIKE '%tolbutamide%' OR a.prod_desc LIKE '%chlorpropamide%')
)
UNION ALL
SELECT 
  'Last 72h' AS period,
  'DPP-4' AS drug_class,
  COUNT(DISTINCT c.hadm_id) * 100.0 / (SELECT n FROM total_n) AS percent
FROM cohort c
WHERE EXISTS (
  SELECT 1 FROM admins a
  WHERE a.hadm_id = c.hadm_id
    AND a.charttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR)
    AND a.charttime < c.dischtime
    AND (a.prod_desc LIKE '%sitagliptin%' OR a.prod_desc LIKE '%saxagliptin%' 
         OR a.prod_desc LIKE '%linagliptin%' OR a.prod_desc LIKE '%alogliptin%')
)
UNION ALL
SELECT 
  'Last 72h' AS period,
  'SGLT2' AS drug_class,
  COUNT(DISTINCT c.hadm_id) * 100.0 / (SELECT n FROM total_n) AS percent
FROM cohort c
WHERE EXISTS (
  SELECT 1 FROM admins a
  WHERE a.hadm_id = c.hadm_id
    AND a.charttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR)
    AND a.charttime < c.dischtime
    AND (a.prod_desc LIKE '%canagliflozin%' OR a.prod_desc LIKE '%dapagliflozin%' 
         OR a.prod_desc LIKE '%empagliflozin%' OR a.prod_desc LIKE '%ertugliflozin%')
)
UNION ALL
SELECT 
  'Last 72h' AS period,
  'GLP-1' AS drug_class,
  COUNT(DISTINCT c.hadm_id) * 100.0 / (SELECT n FROM total_n) AS percent
FROM cohort c
WHERE EXISTS (
  SELECT 1 FROM admins a
  WHERE a.hadm_id = c.hadm_id
    AND a.charttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR)
    AND a.charttime < c.dischtime
    AND (a.prod_desc LIKE '%exenatide%' OR a.prod_desc LIKE '%liraglutide%' 
         OR a.prod_desc LIKE '%dulaglutide%' OR a.prod_desc LIKE '%semaglutide%' 
         OR a.prod_desc LIKE '%albiglutide%' OR a.prod_desc LIKE '%lixisenatide%')
)
UNION ALL
SELECT 
  'Last 72h' AS period,
  'TZD' AS drug_class,
  COUNT(DISTINCT c.hadm_id) * 100.0 / (SELECT n FROM total_n) AS percent
FROM cohort c
WHERE EXISTS (
  SELECT 1 FROM admins a
  WHERE a.hadm_id = c.hadm_id
    AND a.charttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR)
    AND a.charttime < c.dischtime
    AND (a.prod_desc LIKE '%pioglitazone%' OR a.prod_desc LIKE '%rosiglitazone%')
)
ORDER BY period, drug_class;