WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 81 AND 91
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        (icd_version = 9 AND (icd_code LIKE '2500%' OR icd_code LIKE '2501%'))
        OR (icd_version = 10 AND icd_code LIKE 'E11%')
    )
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        (icd_version = 9 AND icd_code LIKE '428%')
        OR (icd_version = 10 AND icd_code LIKE 'I50%')
    )
),

drug_usage AS (
  SELECT 
    c.hadm_id,
    -- Metformin
    MAX(CASE WHEN LOWER(p.drug) LIKE '%metformin%' 
              AND p.starttime < DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) 
              AND c.admittime < COALESCE(p.stoptime, c.dischtime)
            THEN 1 ELSE 0 END) AS metformin_first72,
    MAX(CASE WHEN LOWER(p.drug) LIKE '%metformin%' 
              AND p.starttime < c.dischtime 
              AND DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) < COALESCE(p.stoptime, c.dischtime)
            THEN 1 ELSE 0 END) AS metformin_final48,
    -- Sulfonylureas
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%glyburide%' OR 
                   LOWER(p.drug) LIKE '%glipizide%' OR 
                   LOWER(p.drug) LIKE '%glimepiride%' OR
                   LOWER(p.drug) LIKE '%chlorpropamide%' OR
                   LOWER(p.drug) LIKE '%tolbutamide%' OR
                   LOWER(p.drug) LIKE '%tolazamide%')
              AND p.starttime < DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) 
              AND c.admittime < COALESCE(p.stoptime, c.dischtime)
            THEN 1 ELSE 0 END) AS sulfonylurea_first72,
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%glyburide%' OR 
                   LOWER(p.drug) LIKE '%glipizide%' OR 
                   LOWER(p.drug) LIKE '%glimepiride%' OR
                   LOWER(p.drug) LIKE '%chlorpropamide%' OR
                   LOWER(p.drug) LIKE '%tolbutamide%' OR
                   LOWER(p.drug) LIKE '%tolazamide%')
              AND p.starttime < c.dischtime 
              AND DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) < COALESCE(p.stoptime, c.dischtime)
            THEN 1 ELSE 0 END) AS sulfonylurea_final48,
    -- DPP4 inhibitors
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%sitagliptin%' OR 
                   LOWER(p.drug) LIKE '%saxagliptin%' OR 
                   LOWER(p.drug) LIKE '%linagliptin%' OR 
                   LOWER(p.drug) LIKE '%alogliptin%')
              AND p.starttime < DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) 
              AND c.admittime < COALESCE(p.stoptime, c.dischtime)
            THEN 1 ELSE 0 END) AS dpp4_first72,
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%sitagliptin%' OR 
                   LOWER(p.drug) LIKE '%saxagliptin%' OR 
                   LOWER(p.drug) LIKE '%linagliptin%' OR 
                   LOWER(p.drug) LIKE '%alogliptin%')
              AND p.starttime < c.dischtime 
              AND DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) < COALESCE(p.stoptime, c.dischtime)
            THEN 1 ELSE 0 END) AS dpp4_final48,
    -- SGLT2 inhibitors
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%canagliflozin%' OR 
                   LOWER(p.drug) LIKE '%dapagliflozin%' OR 
                   LOWER(p.drug) LIKE '%empagliflozin%' OR 
                   LOWER(p.drug) LIKE '%ertugliflozin%')
              AND p.starttime < DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) 
              AND c.admittime < COALESCE(p.stoptime, c.dischtime)
            THEN 1 ELSE 0 END) AS sglt2_first72,
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%canagliflozin%' OR 
                   LOWER(p.drug) LIKE '%dapagliflozin%' OR 
                   LOWER(p.drug) LIKE '%empagliflozin%' OR 
                   LOWER(p.drug) LIKE '%ertugliflozin%')
              AND p.starttime < c.dischtime 
              AND DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) < COALESCE(p.stoptime, c.dischtime)
            THEN 1 ELSE 0 END) AS sglt2_final48,
    -- TZDs
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%pioglitazone%' OR 
                   LOWER(p.drug) LIKE '%rosiglitazone%')
              AND p.starttime < DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) 
              AND c.admittime < COALESCE(p.stoptime, c.dischtime)
            THEN 1 ELSE 0 END) AS tzd_first72,
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%pioglitazone%' OR 
                   LOWER(p.drug) LIKE '%rosiglitazone%')
              AND p.starttime < c.dischtime 
              AND DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) < COALESCE(p.stoptime, c.dischtime)
            THEN 1 ELSE 0 END) AS tzd_final48
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    ON c.hadm_id = p.hadm_id
  GROUP BY c.hadm_id
)

SELECT 
  'metformin' AS drug_class,
  AVG(metformin_first72) * 100 AS first_72h_pct,
  AVG(metformin_final48) * 100 AS final_48h_pct,
  (AVG(metformin_final48) - AVG(metformin_first72)) * 100 AS pp_difference
FROM drug_usage

UNION ALL

SELECT 
  'sulfonylurea' AS drug_class,
  AVG(sulfonylurea_first72) * 100 AS first_72h_pct,
  AVG(sulfonylurea_final48) * 100 AS final_48h_pct,
  (AVG(sulfonylurea_final48) - AVG(sulfonylurea_first72)) * 100 AS pp_difference
FROM drug_usage

UNION ALL

SELECT 
  'DPP4' AS drug_class,
  AVG(dpp4_first72) * 100 AS first_72h_pct,
  AVG(dpp4_final48) * 100 AS final_48h_pct,
  (AVG(dpp4_final48) - AVG(dpp4_first72)) * 100 AS pp_difference
FROM drug_usage

UNION ALL

SELECT 
  'SGLT2' AS drug_class,
  AVG(sglt2_first72) * 100 AS first_72h_pct,
  AVG(sglt2_final48) * 100 AS final_48h_pct,
  (AVG(sglt2_final48) - AVG(sglt2_first72)) * 100 AS pp_difference
FROM drug_usage

UNION ALL

SELECT 
  'TZD' AS drug_class,
  AVG(tzd_first72) * 100 AS first_72h_pct,
  AVG(tzd_final48) * 100 AS final_48h_pct,
  (AVG(tzd_final48) - AVG(tzd_first72)) * 100 AS pp_difference
FROM drug_usage;