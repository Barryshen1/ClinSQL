WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.anchor_age BETWEEN 42 AND 52
    AND p.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = p.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 10 AND di.icd_code LIKE 'E1%') 
          OR (di.icd_version = 9 AND di.icd_code LIKE '250%')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = p.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 10 AND di.icd_code LIKE 'I50%') 
          OR (di.icd_version = 9 AND di.icd_code LIKE '428%')
        )
    )
),

first_24h AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN pr.drug LIKE '%insulin%' THEN 1 ELSE 0 END) AS insulin,
    MAX(CASE WHEN pr.drug LIKE '%metformin%' THEN 1 ELSE 0 END) AS metformin,
    MAX(CASE WHEN pr.drug LIKE '%sulfonylurea%' OR pr.drug LIKE '%glipizide%' OR pr.drug LIKE '%glyburide%' OR pr.drug LIKE '%glimepiride%' THEN 1 ELSE 0 END) AS sulfonylurea,
    MAX(CASE WHEN pr.drug LIKE '%dpp4%' OR pr.drug LIKE '%dpp-4%' OR pr.drug LIKE '%sitagliptin%' OR pr.drug LIKE '%saxagliptin%' OR pr.drug LIKE '%linagliptin%' THEN 1 ELSE 0 END) AS dpp4,
    MAX(CASE WHEN pr.drug LIKE '%sglt2%' OR pr.drug LIKE '%sglt-2%' OR pr.drug LIKE '%canagliflozin%' OR pr.drug LIKE '%dapagliflozin%' OR pr.drug LIKE '%empagliflozin%' THEN 1 ELSE 0 END) AS sglt2,
    MAX(CASE WHEN pr.drug LIKE '%glp1%' OR pr.drug LIKE '%glp-1%' OR pr.drug LIKE '%liraglutide%' OR pr.drug LIKE '%dulaglutide%' OR pr.drug LIKE '%semaglutide%' THEN 1 ELSE 0 END) AS glp1,
    MAX(CASE WHEN pr.drug LIKE '%thiazolidinedione%' OR pr.drug LIKE '%pioglitazone%' OR pr.drug LIKE '%rosiglitazone%' THEN 1 ELSE 0 END) AS tzd
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id
    AND c.hadm_id = pr.hadm_id
    AND pr.starttime >= c.admittime
    AND pr.starttime < DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),

final_12h AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN pr.drug LIKE '%insulin%' THEN 1 ELSE 0 END) AS insulin,
    MAX(CASE WHEN pr.drug LIKE '%metformin%' THEN 1 ELSE 0 END) AS metformin,
    MAX(CASE WHEN pr.drug LIKE '%sulfonylurea%' OR pr.drug LIKE '%glipizide%' OR pr.drug LIKE '%glyburide%' OR pr.drug LIKE '%glimepiride%' THEN 1 ELSE 0 END) AS sulfonylurea,
    MAX(CASE WHEN pr.drug LIKE '%dpp4%' OR pr.drug LIKE '%dpp-4%' OR pr.drug LIKE '%sitagliptin%' OR pr.drug LIKE '%saxagliptin%' OR pr.drug LIKE '%linagliptin%' THEN 1 ELSE 0 END) AS dpp4,
    MAX(CASE WHEN pr.drug LIKE '%sglt2%' OR pr.drug LIKE '%sglt-2%' OR pr.drug LIKE '%canagliflozin%' OR pr.drug LIKE '%dapagliflozin%' OR pr.drug LIKE '%empagliflozin%' THEN 1 ELSE 0 END) AS sglt2,
    MAX(CASE WHEN pr.drug LIKE '%glp1%' OR pr.drug LIKE '%glp-1%' OR pr.drug LIKE '%liraglutide%' OR pr.drug LIKE '%dulaglutide%' OR pr.drug LIKE '%semaglutide%' THEN 1 ELSE 0 END) AS glp1,
    MAX(CASE WHEN pr.drug LIKE '%thiazolidinedione%' OR pr.drug LIKE '%pioglitazone%' OR pr.drug LIKE '%rosiglitazone%' THEN 1 ELSE 0 END) AS tzd
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id
    AND c.hadm_id = pr.hadm_id
    AND pr.starttime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR)
    AND pr.starttime < c.dischtime
  GROUP BY c.subject_id, c.hadm_id
)

SELECT 
  'Insulin' AS drug_class,
  ROUND(100.0 * SUM(f24.insulin) / COUNT(*), 1) AS first_24h_pct,
  ROUND(100.0 * SUM(f12.insulin) / COUNT(*), 1) AS final_12h_pct,
  ROUND(100.0 * SUM(f12.insulin) / COUNT(*) - 100.0 * SUM(f24.insulin) / COUNT(*), 1) AS net_change_pp
FROM cohort c
LEFT JOIN first_24h f24 ON c.subject_id = f24.subject_id AND c.hadm_id = f24.hadm_id
LEFT JOIN final_12h f12 ON c.subject_id = f12.subject_id AND c.hadm_id = f12.hadm_id
UNION ALL
SELECT 
  'Metformin',
  ROUND(100.0 * SUM(f24.metformin) / COUNT(*), 1),
  ROUND(100.0 * SUM(f12.metformin) / COUNT(*), 1),
  ROUND(100.0 * SUM(f12.metformin) / COUNT(*) - 100.0 * SUM(f24.metformin) / COUNT(*), 1)
FROM cohort c
LEFT JOIN first_24h f24 ON c.subject_id = f24.subject_id AND c.hadm_id = f24.hadm_id
LEFT JOIN final_12h f12 ON c.subject_id = f12.subject_id AND c.hadm_id = f12.hadm_id
UNION ALL
SELECT 
  'Sulfonylurea',
  ROUND(100.0 * SUM(f24.sulfonylurea) / COUNT(*), 1),
  ROUND(100.0 * SUM(f12.sulfonylurea) / COUNT(*), 1),
  ROUND(100.0 * SUM(f12.sulfonylurea) / COUNT(*) - 100.0 * SUM(f24.sulfonylurea) / COUNT(*), 1)
FROM cohort c
LEFT JOIN first_24h f24 ON c.subject_id = f24.subject_id AND c.hadm_id = f24.hadm_id
LEFT JOIN final_12h f12 ON c.subject_id = f12.subject_id AND c.hadm_id = f12.hadm_id
UNION ALL
SELECT 
  'DPP-4',
  ROUND(100.0 * SUM(f24.dpp4) / COUNT(*), 1),
  ROUND(100.0 * SUM(f12.dpp4) / COUNT(*), 1),
  ROUND(100.0 * SUM(f12.dpp4) / COUNT(*) - 100.0 * SUM(f24.dpp4) / COUNT(*), 1)
FROM cohort c
LEFT JOIN first_24h f24 ON c.subject_id = f24.subject_id AND c.hadm_id = f24.hadm_id
LEFT JOIN final_12h f12 ON c.subject_id = f12.subject_id AND c.hadm_id = f12.hadm_id
UNION ALL
SELECT 
  'SGLT2',
  ROUND(100.0 * SUM(f24.sglt2) / COUNT(*), 1),
  ROUND(100.0 * SUM(f12.sglt2) / COUNT(*), 1),
  ROUND(100.0 * SUM(f12.sglt2) / COUNT(*) - 100.0 * SUM(f24.sglt2) / COUNT(*), 1)
FROM cohort c
LEFT JOIN first_24h f24 ON c.subject_id = f24.subject_id AND c.hadm_id = f24.hadm_id
LEFT JOIN final_12h f12 ON c.subject_id = f12.subject_id AND c.hadm_id = f12.hadm_id
UNION ALL
SELECT 
  'GLP-1',
  ROUND(100.0 * SUM(f24.glp1) / COUNT(*), 1),
  ROUND(100.0 * SUM(f12.glp1) / COUNT(*), 1),
  ROUND(100.0 * SUM(f12.glp1) / COUNT(*) - 100.0 * SUM(f24.glp1) / COUNT(*), 1)
FROM cohort c
LEFT JOIN first_24h f24 ON c.subject_id = f24.subject_id AND c.hadm_id = f24.hadm_id
LEFT JOIN final_12h f12 ON c.subject_id = f12.subject_id AND c.hadm_id = f12.hadm_id
UNION ALL
SELECT 
  'TZD',
  ROUND(100.0 * SUM(f24.tzd) / COUNT(*), 1),
  ROUND(100.0 * SUM(f12.tzd) / COUNT(*), 1),
  ROUND(100.0 * SUM(f12.tzd) / COUNT(*) - 100.0 * SUM(f24.tzd) / COUNT(*), 1)
FROM cohort c
LEFT JOIN first_24h f24 ON c.subject_id = f24.subject_id AND c.hadm_id = f24.hadm_id
LEFT JOIN final_12h f12 ON c.subject_id = f12.subject_id AND c.hadm_id = f12.hadm_id
ORDER BY drug_class;