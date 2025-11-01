WITH cohort AS (
  SELECT 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 42 AND 52
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code LIKE '250%') OR
          (di.icd_version = 10 AND (
            di.icd_code LIKE 'E10.%' OR di.icd_code LIKE 'E11.%' OR 
            di.icd_code LIKE 'E12.%' OR di.icd_code LIKE 'E13.%' OR 
            di.icd_code LIKE 'E14.%'
          ))
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` hf 
      WHERE hf.hadm_id = a.hadm_id
        AND (
          (hf.icd_version = 9 AND hf.icd_code IN ('42821', '42823', '42831', '42841')) OR
          (hf.icd_version = 10 AND hf.icd_code IN (
            'I50.21', 'I50.23', 'I50.31', 'I50.33', 'I50.41', 'I50.43'
          ))
        )
    )
),
exposures_first AS (
  SELECT 
    c.hadm_id,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%insulin%'
             AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
             AND (pr.stoptime IS NULL OR pr.stoptime > c.admittime)
        THEN 1 ELSE 0 END) AS insulin_first,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%metformin%'
             AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
             AND (pr.stoptime IS NULL OR pr.stoptime > c.admittime)
        THEN 1 ELSE 0 END) AS metformin_first,
    MAX(CASE WHEN (LOWER(pr.drug) LIKE '%glimepiride%' OR LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%')
             AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
             AND (pr.stoptime IS NULL OR pr.stoptime > c.admittime)
        THEN 1 ELSE 0 END) AS sulfonylurea_first,
    MAX(CASE WHEN (LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR 
                   LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%')
             AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
             AND (pr.stoptime IS NULL OR pr.stoptime > c.admittime)
        THEN 1 ELSE 0 END) AS dpp4_first,
    MAX(CASE WHEN (LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR 
                   LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%ertugliflozin%')
             AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
             AND (pr.stoptime IS NULL OR pr.stoptime > c.admittime)
        THEN 1 ELSE 0 END) AS sglt2_first,
    MAX(CASE WHEN (LOWER(pr.drug) LIKE '%exenatide%' OR LOWER(pr.drug) LIKE '%liraglutide%' OR 
                   LOWER(pr.drug) LIKE '%dulaglutide%' OR LOWER(pr.drug) LIKE '%semaglutide%' OR 
                   LOWER(pr.drug) LIKE '%albiglutide%' OR LOWER(pr.drug) LIKE '%lixisenatide%')
             AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
             AND (pr.stoptime IS NULL OR pr.stoptime > c.admittime)
        THEN 1 ELSE 0 END) AS glp1_first,
    MAX(CASE WHEN (LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%')
             AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
             AND (pr.stoptime IS NULL OR pr.stoptime > c.admittime)
        THEN 1 ELSE 0 END) AS tzd_first
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON pr.hadm_id = c.hadm_id
  GROUP BY c.hadm_id
),
exposures_final AS (
  SELECT 
    c.hadm_id,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%insulin%'
             AND pr.starttime < c.dischtime
             AND (pr.stoptime IS NULL OR pr.stoptime > TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR))
        THEN 1 ELSE 0 END) AS insulin_final,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%metformin%'
             AND pr.starttime < c.dischtime
             AND (pr.stoptime IS NULL OR pr.stoptime > TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR))
        THEN 1 ELSE 0 END) AS metformin_final,
    MAX(CASE WHEN (LOWER(pr.drug) LIKE '%glimepiride%' OR LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%')
             AND pr.starttime < c.dischtime
             AND (pr.stoptime IS NULL OR pr.stoptime > TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR))
        THEN 1 ELSE 0 END) AS sulfonylurea_final,
    MAX(CASE WHEN (LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR 
                   LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%')
             AND pr.starttime < c.dischtime
             AND (pr.stoptime IS NULL OR pr.stoptime > TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR))
        THEN 1 ELSE 0 END) AS dpp4_final,
    MAX(CASE WHEN (LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR 
                   LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%ertugliflozin%')
             AND pr.starttime < c.dischtime
             AND (pr.stoptime IS NULL OR pr.stoptime > TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR))
        THEN 1 ELSE 0 END) AS sglt2_final,
    MAX(CASE WHEN (LOWER(pr.drug) LIKE '%exenatide%' OR LOWER(pr.drug) LIKE '%liraglutide%' OR 
                   LOWER(pr.drug) LIKE '%dulaglutide%' OR LOWER(pr.drug) LIKE '%semaglutide%' OR 
                   LOWER(pr.drug) LIKE '%albiglutide%' OR LOWER(pr.drug) LIKE '%lixisenatide%')
             AND pr.starttime < c.dischtime
             AND (pr.stoptime IS NULL OR pr.stoptime > TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR))
        THEN 1 ELSE 0 END) AS glp1_final,
    MAX(CASE WHEN (LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%')
             AND pr.starttime < c.dischtime
             AND (pr.stoptime IS NULL OR pr.stoptime > TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR))
        THEN 1 ELSE 0 END) AS tzd_final
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON pr.hadm_id = c.hadm_id
  GROUP BY c.hadm_id
),
combined AS (
  SELECT 
    ef.*,
    fin.insulin_final,
    fin.metformin_final,
    fin.sulfonylurea_final,
    fin.dpp4_final,
    fin.sglt2_final,
    fin.glp1_final,
    fin.tzd_final
  FROM exposures_first ef
  JOIN exposures_final fin ON ef.hadm_id = fin.hadm_id
)
SELECT 
  'Insulin' AS med_class,
  ROUND(100.0 * SUM(insulin_first) / COUNT(*), 2) AS pct_first_24h,
  ROUND(100.0 * SUM(insulin_final) / COUNT(*), 2) AS pct_final_12h,
  ROUND(100.0 * (SUM(insulin_final) - SUM(insulin_first)) / COUNT(*), 2) AS net_change_pp
FROM combined
UNION ALL
SELECT 
  'Metformin' AS med_class,
  ROUND(100.0 * SUM(metformin_first) / COUNT(*), 2) AS pct_first_24h,
  ROUND(100.0 * SUM(metformin_final) / COUNT(*), 2) AS pct_final_12h,
  ROUND(100.0 * (SUM(metformin_final) - SUM(metformin_first)) / COUNT(*), 2) AS net_change_pp
FROM combined
UNION ALL
SELECT 
  'Sulfonylurea' AS med_class,
  ROUND(100.0 * SUM(sulfonylurea_first) / COUNT(*), 2) AS pct_first_24h,
  ROUND(100.0 * SUM(sulfonylurea_final) / COUNT(*), 2) AS pct_final_12h,
  ROUND(100.0 * (SUM(sulfonylurea_final) - SUM(sulfonylurea_first)) / COUNT(*), 2) AS net_change_pp
FROM combined
UNION ALL
SELECT 
  'DPP-4' AS med_class,
  ROUND(100.0 * SUM(dpp4_first) / COUNT(*), 2) AS pct_first_24h,
  ROUND(100.0 * SUM(dpp4_final) / COUNT(*), 2) AS pct_final_12h,
  ROUND(100.0 * (SUM(dpp4_final) - SUM(dpp4_first)) / COUNT(*), 2) AS net_change_pp
FROM combined
UNION ALL
SELECT 
  'SGLT2' AS med_class,
  ROUND(100.0 * SUM(sglt2_first) / COUNT(*), 2) AS pct_first_24h,
  ROUND(100.0 * SUM(sglt2_final) / COUNT(*), 2) AS pct_final_12h,
  ROUND(100.0 * (SUM(sglt2_final) - SUM(sglt2_first)) / COUNT(*), 2) AS net_change_pp
FROM combined
UNION ALL
SELECT 
  'GLP-1' AS med_class,
  ROUND(100.0 * SUM(glp1_first) / COUNT(*), 2) AS pct_first_24h,
  ROUND(100.0 * SUM(glp1_final) / COUNT(*), 2) AS pct_final_12h,
  ROUND(100.0 * (SUM(glp1_final) - SUM(glp1_first)) / COUNT(*), 2) AS net_change_pp
FROM combined
UNION ALL
SELECT 
  'TZD' AS med_class,
  ROUND(100.0 * SUM(tzd_first) / COUNT(*), 2) AS pct_first_24h,
  ROUND(100.0 * SUM(tzd_final) / COUNT(*), 2) AS pct_final_12h,
  ROUND(100.0 * (SUM(tzd_final) - SUM(tzd_first)) / COUNT(*), 2) AS net_change_pp
FROM combined
ORDER BY med_class;