WITH diabetes_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 10 AND icd_code LIKE 'E1[0-4]%')
     OR (icd_version = 9 AND icd_code LIKE '250%')
),
hf_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 10 AND icd_code LIKE 'I50%')
     OR (icd_version = 9 AND icd_code LIKE '428%')
),
cohort AS (
  SELECT DISTINCT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN diabetes_hadm dh ON a.hadm_id = dh.hadm_id
  INNER JOIN hf_hadm hh ON a.hadm_id = hh.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
),
med_presc AS (
  SELECT 
    c.hadm_id, 
    c.admittime, 
    c.dischtime, 
    pr.drug, 
    pr.starttime,
    CASE 
      WHEN pr.starttime >= c.admittime 
           AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR) 
      THEN 'first72'
      WHEN pr.starttime > TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) 
           AND pr.starttime <= c.dischtime 
      THEN 'last48'
      ELSE 'other' 
    END AS period
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON c.hadm_id = pr.hadm_id
  WHERE pr.route = 'PO'
    AND pr.drug IS NOT NULL
    AND pr.starttime IS NOT NULL
),
classified AS (
  SELECT 
    hadm_id, 
    period,
    MAX(CASE WHEN drug LIKE '%Metformin%' THEN 1 ELSE 0 END) AS metformin,
    MAX(CASE WHEN drug LIKE '%Glimepiride%' OR drug LIKE '%Glipizide%' OR drug LIKE '%Glyburide%' OR drug LIKE '%Chlorpropamide%' THEN 1 ELSE 0 END) AS sulfonylurea,
    MAX(CASE WHEN drug LIKE '%Sitagliptin%' OR drug LIKE '%Saxagliptin%' OR drug LIKE '%Linagliptin%' OR drug LIKE '%Alogliptin%' THEN 1 ELSE 0 END) AS dpp4,
    MAX(CASE WHEN drug LIKE '%Canagliflozin%' OR drug LIKE '%Dapagliflozin%' OR drug LIKE '%Empagliflozin%' OR drug LIKE '%Ertugliflozin%' THEN 1 ELSE 0 END) AS sglt2,
    MAX(CASE WHEN drug LIKE '%Pioglitazone%' OR drug LIKE '%Rosiglitazone%' THEN 1 ELSE 0 END) AS tzd
  FROM med_presc
  WHERE period IN ('first72', 'last48')
  GROUP BY hadm_id, period
),
agg_first AS (
  SELECT 
    SUM(metformin) AS n_met_f,
    SUM(sulfonylurea) AS n_sulf_f,
    SUM(dpp4) AS n_dpp_f,
    SUM(sglt2) AS n_sglt_f,
    SUM(tzd) AS n_tzd_f
  FROM classified 
  WHERE period = 'first72'
),
agg_last AS (
  SELECT 
    SUM(metformin) AS n_met_l,
    SUM(sulfonylurea) AS n_sulf_l,
    SUM(dpp4) AS n_dpp_l,
    SUM(sglt2) AS n_sglt_l,
    SUM(tzd) AS n_tzd_l
  FROM classified 
  WHERE period = 'last48'
),
total_cte AS (
  SELECT COUNT(*) AS total_n 
  FROM cohort
)
SELECT 
  'Metformin' AS drug_class,
  ROUND(COALESCE(n_met_f, 0) / total_n * 100, 2) AS first_72h_rate,
  ROUND(COALESCE(n_met_l, 0) / total_n * 100, 2) AS last_48h_rate
FROM agg_first, agg_last, total_cte
UNION ALL
SELECT 
  'Sulfonylureas' AS drug_class,
  ROUND(COALESCE(n_sulf_f, 0) / total_n * 100, 2) AS first_72h_rate,
  ROUND(COALESCE(n_sulf_l, 0) / total_n * 100, 2) AS last_48h_rate
FROM agg_first, agg_last, total_cte
UNION ALL
SELECT 
  'DPP-4' AS drug_class,
  ROUND(COALESCE(n_dpp_f, 0) / total_n * 100, 2) AS first_72h_rate,
  ROUND(COALESCE(n_dpp_l, 0) / total_n * 100, 2) AS last_48h_rate
FROM agg_first, agg_last, total_cte
UNION ALL
SELECT 
  'SGLT2' AS drug_class,
  ROUND(COALESCE(n_sglt_f, 0) / total_n * 100, 2) AS first_72h_rate,
  ROUND(COALESCE(n_sglt_l, 0) / total_n * 100, 2) AS last_48h_rate
FROM agg_first, agg_last, total_cte
UNION ALL
SELECT 
  'Thiazolidinediones' AS drug_class,
  ROUND(COALESCE(n_tzd_f, 0) / total_n * 100, 2) AS first_72h_rate,
  ROUND(COALESCE(n_tzd_l, 0) / total_n * 100, 2) AS last_48h_rate
FROM agg_first, agg_last, total_cte
ORDER BY drug_class;