WITH base AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 71 AND 81
),
diabetes AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 10 AND (icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%'))
    OR
    (icd_version = 9 AND icd_code LIKE '250%')
),
heart_failure AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 10 AND (icd_code LIKE 'I50.2%' OR icd_code LIKE 'I50.3%'))
    OR
    (icd_version = 9 AND icd_code IN ('42821','42822','42823','42831','42832','42833','42841','42842','42843'))
),
cohort AS (
  SELECT base.*
  FROM base
  INNER JOIN diabetes d ON base.hadm_id = d.hadm_id
  INNER JOIN heart_failure hf ON base.hadm_id = hf.hadm_id
),
drug_orders AS (
  SELECT 
    p.hadm_id,
    p.starttime,
    CASE WHEN LOWER(p.drug) LIKE '%metformin%' THEN 1 ELSE 0 END AS metformin,
    CASE WHEN LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glimepiride%' OR LOWER(p.drug) LIKE '%gliclazide%' THEN 1 ELSE 0 END AS sulfonylureas,
    CASE WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' THEN 1 ELSE 0 END AS dpp4,
    CASE WHEN LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%ertugliflozin%' THEN 1 ELSE 0 END AS sglt2,
    CASE WHEN LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' THEN 1 ELSE 0 END AS thiazolidinediones
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE 
    (LOWER(p.drug) LIKE '%metformin%') OR
    (LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glimepiride%' OR LOWER(p.drug) LIKE '%gliclazide%') OR
    (LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%') OR
    (LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%ertugliflozin%') OR
    (LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%')
),
first_initiation AS (
  SELECT 
    hadm_id,
    MIN(CASE WHEN metformin = 1 THEN starttime ELSE NULL END) AS first_metformin,
    MIN(CASE WHEN sulfonylureas = 1 THEN starttime ELSE NULL END) AS first_sulfonylureas,
    MIN(CASE WHEN dpp4 = 1 THEN starttime ELSE NULL END) AS first_dpp4,
    MIN(CASE WHEN sglt2 = 1 THEN starttime ELSE NULL END) AS first_sglt2,
    MIN(CASE WHEN thiazolidinediones = 1 THEN starttime ELSE NULL END) AS first_thiazolidinediones
  FROM drug_orders
  GROUP BY hadm_id
),
flags AS (
  SELECT 
    c.hadm_id,
    -- Metformin
    CASE WHEN fi.first_metformin IS NOT NULL 
         AND fi.first_metformin >= c.admittime 
         AND fi.first_metformin <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR) 
         THEN 1 ELSE 0 END AS metformin_72h,
    CASE WHEN fi.first_metformin IS NOT NULL 
         AND fi.first_metformin >= TIMESTAMP_ADD(c.dischtime, INTERVAL -48 HOUR) 
         AND fi.first_metformin <= c.dischtime 
         THEN 1 ELSE 0 END AS metformin_48h,
    -- Sulfonylureas
    CASE WHEN fi.first_sulfonylureas IS NOT NULL 
         AND fi.first_sulfonylureas >= c.admittime 
         AND fi.first_sulfonylureas <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR) 
         THEN 1 ELSE 0 END AS sulfonylureas_72h,
    CASE WHEN fi.first_sulfonylureas IS NOT NULL 
         AND fi.first_sulfonylureas >= TIMESTAMP_ADD(c.dischtime, INTERVAL -48 HOUR) 
         AND fi.first_sulfonylureas <= c.dischtime 
         THEN 1 ELSE 0 END AS sulfonylureas_48h,
    -- DPP-4
    CASE WHEN fi.first_dpp4 IS NOT NULL 
         AND fi.first_dpp4 >= c.admittime 
         AND fi.first_dpp4 <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR) 
         THEN 1 ELSE 0 END AS dpp4_72h,
    CASE WHEN fi.first_dpp4 IS NOT NULL 
         AND fi.first_dpp4 >= TIMESTAMP_ADD(c.dischtime, INTERVAL -48 HOUR) 
         AND fi.first_dpp4 <= c.dischtime 
         THEN 1 ELSE 0 END AS dpp4_48h,
    -- SGLT2
    CASE WHEN fi.first_sglt2 IS NOT NULL 
         AND fi.first_sglt2 >= c.admittime 
         AND fi.first_sglt2 <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR) 
         THEN 1 ELSE 0 END AS sglt2_72h,
    CASE WHEN fi.first_sglt2 IS NOT NULL 
         AND fi.first_sglt2 >= TIMESTAMP_ADD(c.dischtime, INTERVAL -48 HOUR) 
         AND fi.first_sglt2 <= c.dischtime 
         THEN 1 ELSE 0 END AS sglt2_48h,
    -- Thiazolidinediones
    CASE WHEN fi.first_thiazolidinediones IS NOT NULL 
         AND fi.first_thiazolidinediones >= c.admittime 
         AND fi.first_thiazolidinediones <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR) 
         THEN 1 ELSE 0 END AS thiazolidinediones_72h,
    CASE WHEN fi.first_thiazolidinediones IS NOT NULL 
         AND fi.first_thiazolidinediones >= TIMESTAMP_ADD(c.dischtime, INTERVAL -48 HOUR) 
         AND fi.first_thiazolidinediones <= c.dischtime 
         THEN 1 ELSE 0 END AS thiazolidinediones_48h
  FROM cohort c
  LEFT JOIN first_initiation fi ON c.hadm_id = fi.hadm_id
),
totals AS (
  SELECT COUNT(*) AS total FROM cohort
)
SELECT 
  'metformin' AS drug_class,
  SUM(metformin_72h) * 100.0 / total AS rate_72h,
  SUM(metformin_48h) * 100.0 / total AS rate_48h
FROM flags, totals
GROUP BY total
UNION ALL
SELECT 
  'sulfonylureas',
  SUM(sulfonylureas_72h) * 100.0 / total,
  SUM(sulfonylureas_48h) * 100.0 / total
FROM flags, totals
GROUP BY total
UNION ALL
SELECT 
  'DPP-4',
  SUM(dpp4_72h) * 100.0 / total,
  SUM(dpp4_48h) * 100.0 / total
FROM flags, totals
GROUP BY total
UNION ALL
SELECT 
  'SGLT2',
  SUM(sglt2_72h) * 100.0 / total,
  SUM(sglt2_48h) * 100.0 / total
FROM flags, totals
GROUP BY total
UNION ALL
SELECT 
  'thiazolidinediones',
  SUM(thiazolidinediones_72h) * 100.0 / total,
  SUM(thiazolidinediones_48h) * 100.0 / total
FROM flags, totals
GROUP BY total;