WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
),

drug_classes AS (
  SELECT 
    subject_id,
    hadm_id,
    -- Check for metformin
    MAX(CASE WHEN LOWER(drug) LIKE '%metformin%' THEN 1 ELSE 0 END) AS metformin,
    -- Check for sulfonylureas: common ones are glipizide, glyburide, glimepiride
    MAX(CASE WHEN LOWER(drug) LIKE '%glipizide%' OR 
                 LOWER(drug) LIKE '%glyburide%' OR 
                 LOWER(drug) LIKE '%glimepiride%' THEN 1 ELSE 0 END) AS sulfonylureas,
    -- Check for DPP-4 inhibitors: sitagliptin, saxagliptin, linagliptin, alogliptin
    MAX(CASE WHEN LOWER(drug) LIKE '%sitagliptin%' OR 
                 LOWER(drug) LIKE '%saxagliptin%' OR 
                 LOWER(drug) LIKE '%linagliptin%' OR 
                 LOWER(drug) LIKE '%alogliptin%' THEN 1 ELSE 0 END) AS dpp4,
    -- Check for SGLT2 inhibitors: canagliflozin, dapagliflozin, empagliflozin
    MAX(CASE WHEN LOWER(drug) LIKE '%canagliflozin%' OR 
                 LOWER(drug) LIKE '%dapagliflozin%' OR 
                 LOWER(drug) LIKE '%empagliflozin%' THEN 1 ELSE 0 END) AS sglt2
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  GROUP BY subject_id, hadm_id
),

first_48h AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    -- Check if metformin was given in first 48h
    MAX(CASE WHEN LOWER(drug) LIKE '%metformin%' AND 
                 starttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR) AND
                 (stoptime IS NULL OR stoptime >= c.admittime) THEN 1 ELSE 0 END) AS metformin,
    -- Check sulfonylureas
    MAX(CASE WHEN (LOWER(drug) LIKE '%glipizide%' OR 
                   LOWER(drug) LIKE '%glyburide%' OR 
                   LOWER(drug) LIKE '%glimepiride%') AND
                 starttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR) AND
                 (stoptime IS NULL OR stoptime >= c.admittime) THEN 1 ELSE 0 END) AS sulfonylureas,
    -- Check DPP-4
    MAX(CASE WHEN (LOWER(drug) LIKE '%sitagliptin%' OR 
                   LOWER(drug) LIKE '%saxagliptin%' OR 
                   LOWER(drug) LIKE '%linagliptin%' OR 
                   LOWER(drug) LIKE '%alogliptin%') AND
                 starttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR) AND
                 (stoptime IS NULL OR stoptime >= c.admittime) THEN 1 ELSE 0 END) AS dpp4,
    -- Check SGLT2
    MAX(CASE WHEN (LOWER(drug) LIKE '%canagliflozin%' OR 
                   LOWER(drug) LIKE '%dapagliflozin%' OR 
                   LOWER(drug) LIKE '%empagliflozin%') AND
                 starttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR) AND
                 (stoptime IS NULL OR stoptime >= c.admittime) THEN 1 ELSE 0 END) AS sglt2
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  GROUP BY c.subject_id, c.hadm_id
),

last_12h AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    -- Check if metformin was given in last 12h
    MAX(CASE WHEN LOWER(drug) LIKE '%metformin%' AND 
                 starttime <= c.dischtime AND
                 (stoptime IS NULL OR stoptime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR)) THEN 1 ELSE 0 END) AS metformin,
    -- Check sulfonylureas
    MAX(CASE WHEN (LOWER(drug) LIKE '%glipizide%' OR 
                   LOWER(drug) LIKE '%glyburide%' OR 
                   LOWER(drug) LIKE '%glimepiride%') AND
                 starttime <= c.dischtime AND
                 (stoptime IS NULL OR stoptime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR)) THEN 1 ELSE 0 END) AS sulfonylureas,
    -- Check DPP-4
    MAX(CASE WHEN (LOWER(drug) LIKE '%sitagliptin%' OR 
                   LOWER(drug) LIKE '%saxagliptin%' OR 
                   LOWER(drug) LIKE '%linagliptin%' OR 
                   LOWER(drug) LIKE '%alogliptin%') AND
                 starttime <= c.dischtime AND
                 (stoptime IS NULL OR stoptime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR)) THEN 1 ELSE 0 END) AS dpp4,
    -- Check SGLT2
    MAX(CASE WHEN (LOWER(drug) LIKE '%canagliflozin%' OR 
                   LOWER(drug) LIKE '%dapagliflozin%' OR 
                   LOWER(drug) LIKE '%empagliflozin%') AND
                 starttime <= c.dischtime AND
                 (stoptime IS NULL OR stoptime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR)) THEN 1 ELSE 0 END) AS sglt2
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  GROUP BY c.subject_id, c.hadm_id
)

SELECT 
  'Metformin' AS drug_class,
  ROUND(100.0 * SUM(f.metformin) / COUNT(*), 1) AS prevalence_first_48h,
  ROUND(100.0 * SUM(l.metformin) / COUNT(*), 1) AS prevalence_last_12h,
  ROUND(100.0 * SUM(l.metformin) / COUNT(*) - 100.0 * SUM(f.metformin) / COUNT(*), 1) AS net_change_percentage_points
FROM cohort c
LEFT JOIN first_48h f ON c.hadm_id = f.hadm_id
LEFT JOIN last_12h l ON c.hadm_id = l.hadm_id

UNION ALL

SELECT 
  'Sulfonylureas',
  ROUND(100.0 * SUM(f.sulfonylureas) / COUNT(*), 1),
  ROUND(100.0 * SUM(l.sulfonylureas) / COUNT(*), 1),
  ROUND(100.0 * SUM(l.sulfonylureas) / COUNT(*) - 100.0 * SUM(f.sulfonylureas) / COUNT(*), 1)
FROM cohort c
LEFT JOIN first_48h f ON c.hadm_id = f.hadm_id
LEFT JOIN last_12h l ON c.hadm_id = l.hadm_id

UNION ALL

SELECT 
  'DPP-4',
  ROUND(100.0 * SUM(f.dpp4) / COUNT(*), 1),
  ROUND(100.0 * SUM(l.dpp4) / COUNT(*), 1),
  ROUND(100.0 * SUM(l.dpp4) / COUNT(*) - 100.0 * SUM(f.dpp4) / COUNT(*), 1)
FROM cohort c
LEFT JOIN first_48h f ON c.hadm_id = f.hadm_id
LEFT JOIN last_12h l ON c.hadm_id = l.hadm_id

UNION ALL

SELECT 
  'SGLT2',
  ROUND(100.0 * SUM(f.sglt2) / COUNT(*), 1),
  ROUND(100.0 * SUM(l.sglt2) / COUNT(*), 1),
  ROUND(100.0 * SUM(l.sglt2) / COUNT(*) - 100.0 * SUM(f.sglt2) / COUNT(*), 1)
FROM cohort c
LEFT JOIN first_48h f ON c.hadm_id = f.hadm_id
LEFT JOIN last_12h l ON c.hadm_id = l.hadm_id;