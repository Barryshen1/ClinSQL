WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 42 AND 52
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM (
        SELECT 
          hadm_id,
          MAX(CASE WHEN 
                (icd_version = 9 AND icd_code LIKE '250%') OR
                (icd_version = 10 AND icd_code LIKE 'E1%' AND icd_code IN ('E10', 'E11', 'E12', 'E13', 'E14'))
              THEN 1 ELSE 0 END) AS diabetes_flag,
          MAX(CASE WHEN 
                (icd_version = 9 AND icd_code LIKE '428%') OR
                (icd_version = 10 AND (icd_code LIKE 'I50%' OR icd_code IN ('I11.0', 'I13.0', 'I13.2')))
              THEN 1 ELSE 0 END) AS hf_flag
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        GROUP BY hadm_id
      )
      WHERE diabetes_flag = 1 AND hf_flag = 1
    )
),

class_flags AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    -- Insulin
    MAX(CASE WHEN LOWER(p.drug) LIKE '%insulin%' 
              AND p.starttime <= DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
              AND COALESCE(p.stoptime, c.dischtime) >= c.admittime
              AND p.starttime <= c.dischtime 
             THEN 1 ELSE 0 END) AS insulin_first_24h,
    MAX(CASE WHEN LOWER(p.drug) LIKE '%insulin%' 
              AND p.starttime <= c.dischtime
              AND COALESCE(p.stoptime, c.dischtime) >= GREATEST(c.admittime, DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR))
             THEN 1 ELSE 0 END) AS insulin_final_12h,

    -- Metformin
    MAX(CASE WHEN LOWER(p.drug) LIKE '%metformin%' 
              AND p.starttime <= DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
              AND COALESCE(p.stoptime, c.dischtime) >= c.admittime
              AND p.starttime <= c.dischtime 
             THEN 1 ELSE 0 END) AS metformin_first_24h,
    MAX(CASE WHEN LOWER(p.drug) LIKE '%metformin%' 
              AND p.starttime <= c.dischtime
              AND COALESCE(p.stoptime, c.dischtime) >= GREATEST(c.admittime, DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR))
             THEN 1 ELSE 0 END) AS metformin_final_12h,

    -- Sulfonylurea
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%glyburide%' OR 
                   LOWER(p.drug) LIKE '%glipizide%' OR 
                   LOWER(p.drug) LIKE '%glimepiride%' OR 
                   LOWER(p.drug) LIKE '%gliclazide%' OR 
                   LOWER(p.drug) LIKE '%tolbutamide%' OR 
                   LOWER(p.drug) LIKE '%chlorpropamide%' OR 
                   LOWER(p.drug) LIKE '%tolazamide%')
              AND p.starttime <= DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
              AND COALESCE(p.stoptime, c.dischtime) >= c.admittime
              AND p.starttime <= c.dischtime 
             THEN 1 ELSE 0 END) AS sulfonylurea_first_24h,
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%glyburide%' OR 
                   LOWER(p.drug) LIKE '%glipizide%' OR 
                   LOWER(p.drug) LIKE '%glimepiride%' OR 
                   LOWER(p.drug) LIKE '%gliclazide%' OR 
                   LOWER(p.drug) LIKE '%tolbutamide%' OR 
                   LOWER(p.drug) LIKE '%chlorpropamide%' OR 
                   LOWER(p.drug) LIKE '%tolazamide%')
              AND p.starttime <= c.dischtime
              AND COALESCE(p.stoptime, c.dischtime) >= GREATEST(c.admittime, DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR))
             THEN 1 ELSE 0 END) AS sulfonylurea_final_12h,

    -- DPP-4
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%sitagliptin%' OR 
                   LOWER(p.drug) LIKE '%saxagliptin%' OR 
                   LOWER(p.drug) LIKE '%linagliptin%' OR 
                   LOWER(p.drug) LIKE '%alogliptin%')
              AND p.starttime <= DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
              AND COALESCE(p.stoptime, c.dischtime) >= c.admittime
              AND p.starttime <= c.dischtime 
             THEN 1 ELSE 0 END) AS dpp4_first_24h,
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%sitagliptin%' OR 
                   LOWER(p.drug) LIKE '%saxagliptin%' OR 
                   LOWER(p.drug) LIKE '%linagliptin%' OR 
                   LOWER(p.drug) LIKE '%alogliptin%')
              AND p.starttime <= c.dischtime
              AND COALESCE(p.stoptime, c.dischtime) >= GREATEST(c.admittime, DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR))
             THEN 1 ELSE 0 END) AS dpp4_final_12h,

    -- SGLT2
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%canagliflozin%' OR 
                   LOWER(p.drug) LIKE '%dapagliflozin%' OR 
                   LOWER(p.drug) LIKE '%empagliflozin%' OR 
                   LOWER(p.drug) LIKE '%ertugliflozin%')
              AND p.starttime <= DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
              AND COALESCE(p.stoptime, c.dischtime) >= c.admittime
              AND p.starttime <= c.dischtime 
             THEN 1 ELSE 0 END) AS sglt2_first_24h,
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%canagliflozin%' OR 
                   LOWER(p.drug) LIKE '%dapagliflozin%' OR 
                   LOWER(p.drug) LIKE '%empagliflozin%' OR 
                   LOWER(p.drug) LIKE '%ertugliflozin%')
              AND p.starttime <= c.dischtime
              AND COALESCE(p.stoptime, c.dischtime) >= GREATEST(c.admittime, DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR))
             THEN 1 ELSE 0 END) AS sglt2_final_12h,

    -- GLP-1
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%exenatide%' OR 
                   LOWER(p.drug) LIKE '%liraglutide%' OR 
                   LOWER(p.drug) LIKE '%dulaglutide%' OR 
                   LOWER(p.drug) LIKE '%semaglutide%' OR 
                   LOWER(p.drug) LIKE '%lixisenatide%')
              AND p.starttime <= DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
              AND COALESCE(p.stoptime, c.dischtime) >= c.admittime
              AND p.starttime <= c.dischtime 
             THEN 1 ELSE 0 END) AS glp1_first_24h,
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%exenatide%' OR 
                   LOWER(p.drug) LIKE '%liraglutide%' OR 
                   LOWER(p.drug) LIKE '%dulaglutide%' OR 
                   LOWER(p.drug) LIKE '%semaglutide%' OR 
                   LOWER(p.drug) LIKE '%lixisenatide%')
              AND p.starttime <= c.dischtime
              AND COALESCE(p.stoptime, c.dischtime) >= GREATEST(c.admittime, DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR))
             THEN 1 ELSE 0 END) AS glp1_final_12h,

    -- TZD
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%pioglitazone%' OR 
                   LOWER(p.drug) LIKE '%rosiglitazone%')
              AND p.starttime <= DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
              AND COALESCE(p.stoptime, c.dischtime) >= c.admittime
              AND p.starttime <= c.dischtime 
             THEN 1 ELSE 0 END) AS tzd_first_24h,
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%pioglitazone%' OR 
                   LOWER(p.drug) LIKE '%rosiglitazone%')
              AND p.starttime <= c.dischtime
              AND COALESCE(p.stoptime, c.dischtime) >= GREATEST(c.admittime, DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR))
             THEN 1 ELSE 0 END) AS tzd_final_12h

  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  GROUP BY c.subject_id, c.hadm_id
),

unpiv AS (
  SELECT subject_id, 'Insulin' AS class, insulin_first_24h AS first_24h, insulin_final_12h AS final_12h FROM class_flags
  UNION ALL
  SELECT subject_id, 'Metformin', metformin_first_24h, metformin_final_12h FROM class_flags
  UNION ALL
  SELECT subject_id, 'Sulfonylurea', sulfonylurea_first_24h, sulfonylurea_final_12h FROM class_flags
  UNION ALL
  SELECT subject_id, 'DPP-4', dpp4_first_24h, dpp4_final_12h FROM class_flags
  UNION ALL
  SELECT subject_id, 'SGLT2', sglt2_first_24h, sglt2_final_12h FROM class_flags
  UNION ALL
  SELECT subject_id, 'GLP-1', glp1_first_24h, glp1_final_12h FROM class_flags
  UNION ALL
  SELECT subject_id, 'TZD', tzd_first_24h, tzd_final_12h FROM class_flags
)

SELECT 
  class,
  ROUND(AVG(first_24h) * 100, 2) AS first_24h_percent,
  ROUND(AVG(final_12h) * 100, 2) AS final_12h_percent,
  ROUND((AVG(final_12h) - AVG(first_24h)) * 100, 2) AS net_change_pp
FROM unpiv
GROUP BY class
ORDER BY class;