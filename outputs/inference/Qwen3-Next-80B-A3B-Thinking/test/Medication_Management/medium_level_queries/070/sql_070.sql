WITH patients_cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
),

prescriptions_with_classes AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.starttime,
    c.admittime,
    c.dischtime,
    CASE 
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 1 ELSE 0 
    END AS is_metformin,
    CASE 
      WHEN LOWER(p.drug) LIKE '%glipizide%' OR 
           LOWER(p.drug) LIKE '%glyburide%' OR 
           LOWER(p.drug) LIKE '%glimepiride%' OR 
           LOWER(p.drug) LIKE '%tolbutamide%' OR 
           LOWER(p.drug) LIKE '%chlorpropamide%' OR 
           LOWER(p.drug) LIKE '%acetohexamide%' OR 
           LOWER(p.drug) LIKE '%tolazamide%' OR 
           LOWER(p.drug) LIKE '%gliclazide%' OR 
           LOWER(p.drug) LIKE '%glibenclamide%' 
      THEN 1 ELSE 0 
    END AS is_sulfonylurea,
    CASE 
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR 
           LOWER(p.drug) LIKE '%saxagliptin%' OR 
           LOWER(p.drug) LIKE '%linagliptin%' OR 
           LOWER(p.drug) LIKE '%alogliptin%' OR 
           LOWER(p.drug) LIKE '%vildagliptin%' 
      THEN 1 ELSE 0 
    END AS is_dpp4,
    CASE 
      WHEN LOWER(p.drug) LIKE '%canagliflozin%' OR 
           LOWER(p.drug) LIKE '%dapagliflozin%' OR 
           LOWER(p.drug) LIKE '%empagliflozin%' OR 
           LOWER(p.drug) LIKE '%ertugliflozin%' 
      THEN 1 ELSE 0 
    END AS is_sglt2
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN patients_cohort c ON p.hadm_id = c.hadm_id
),

first_48h AS (
  SELECT 
    subject_id,
    MAX(is_metformin) AS metformin_first48,
    MAX(is_sulfonylurea) AS sulfonylurea_first48,
    MAX(is_dpp4) AS dpp4_first48,
    MAX(is_sglt2) AS sglt2_first48
  FROM prescriptions_with_classes
  WHERE starttime BETWEEN admittime AND admittime + INTERVAL '48' HOUR
  GROUP BY subject_id
),

last_12h AS (
  SELECT 
    subject_id,
    MAX(is_metformin) AS metformin_last12,
    MAX(is_sulfonylurea) AS sulfonylurea_last12,
    MAX(is_dpp4) AS dpp4_last12,
    MAX(is_sglt2) AS sglt2_last12
  FROM prescriptions_with_classes
  WHERE starttime BETWEEN dischtime - INTERVAL '12' HOUR AND dischtime
  GROUP BY subject_id
),

all_subjects AS (
  SELECT subject_id FROM patients_cohort
)

SELECT 
  'metformin' AS drug_class,
  ROUND(100.0 * AVG(COALESCE(f.metformin_first48, 0)), 2) AS first_48h_prevalence,
  ROUND(100.0 * AVG(COALESCE(l.metformin_last12, 0)), 2) AS last_12h_prevalence,
  ROUND(100.0 * (AVG(COALESCE(l.metformin_last12, 0)) - AVG(COALESCE(f.metformin_first48, 0))), 2) AS net_change
FROM all_subjects a
LEFT JOIN first_48h f ON a.subject_id = f.subject_id
LEFT JOIN last_12h l ON a.subject_id = l.subject_id

UNION ALL

SELECT 
  'sulfonylureas' AS drug_class,
  ROUND(100.0 * AVG(COALESCE(f.sulfonylurea_first48, 0)), 2),
  ROUND(100.0 * AVG(COALESCE(l.sulfonylurea_last12, 0)), 2),
  ROUND(100.0 * (AVG(COALESCE(l.sulfonylurea_last12, 0)) - AVG(COALESCE(f.sulfonylurea_first48, 0))), 2)
FROM all_subjects a
LEFT JOIN first_48h f ON a.subject_id = f.subject_id
LEFT JOIN last_12h l ON a.subject_id = l.subject_id

UNION ALL

SELECT 
  'DPP-4' AS drug_class,
  ROUND(100.0 * AVG(COALESCE(f.dpp4_first48, 0)), 2),
  ROUND(100.0 * AVG(COALESCE(l.dpp4_last12, 0)), 2),
  ROUND(100.0 * (AVG(COALESCE(l.dpp4_last12, 0)) - AVG(COALESCE(f.dpp4_first48, 0))), 2)
FROM all_subjects a
LEFT JOIN first_48h f ON a.subject_id = f.subject_id
LEFT JOIN last_12h l ON a.subject_id = l.subject_id

UNION ALL

SELECT 
  'SGLT2' AS drug_class,
  ROUND(100.0 * AVG(COALESCE(f.sglt2_first48, 0)), 2),
  ROUND(100.0 * AVG(COALESCE(l.sglt2_last12, 0)), 2),
  ROUND(100.0 * (AVG(COALESCE(l.sglt2_last12, 0)) - AVG(COALESCE(f.sglt2_first48, 0))), 2)
FROM all_subjects a
LEFT JOIN first_48h f ON a.subject_id = f.subject_id
LEFT JOIN last_12h l ON a.subject_id = l.subject_id;