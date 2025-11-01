WITH population AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 53 AND 63
    AND a.dischtime IS NOT NULL
),
diabetes AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND (icd_code LIKE '250.%' OR icd_code LIKE '249.%'))
    OR
    (icd_version = 10 AND (icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%'))
),
heart_failure AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '428.%')
    OR
    (icd_version = 10 AND icd_code LIKE 'I50.%')
),
target_population AS (
  SELECT p.hadm_id, p.admittime, p.dischtime
  FROM population p
  INNER JOIN diabetes d ON p.hadm_id = d.hadm_id
  INNER JOIN heart_failure hf ON p.hadm_id = hf.hadm_id
),
glp1_orders AS (
  SELECT 
    hadm_id,
    MIN(starttime) AS first_order_time
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    (LOWER(drug) LIKE '%exenatide%' 
     OR LOWER(drug) LIKE '%liraglutide%' 
     OR LOWER(drug) LIKE '%dulaglutide%' 
     OR LOWER(drug) LIKE '%semaglutide%')
    AND (LOWER(route) LIKE '%subcut%' OR LOWER(route) = 'sc')
  GROUP BY hadm_id
),
flags AS (
  SELECT
    tp.hadm_id,
    tp.admittime,
    tp.dischtime,
    go.first_order_time,
    CASE WHEN go.first_order_time <= TIMESTAMP_ADD(tp.admittime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END AS within_24h,
    CASE WHEN go.first_order_time >= TIMESTAMP_SUB(tp.dischtime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END AS within_12h_before_discharge
  FROM target_population tp
  LEFT JOIN glp1_orders go ON tp.hadm_id = go.hadm_id
)
SELECT 
  SAFE_DIVIDE(SUM(within_24h), COUNT(*)) * 100 AS pct_24h,
  SAFE_DIVIDE(SUM(within_12h_before_discharge), COUNT(*)) * 100 AS pct_12h
FROM flags;