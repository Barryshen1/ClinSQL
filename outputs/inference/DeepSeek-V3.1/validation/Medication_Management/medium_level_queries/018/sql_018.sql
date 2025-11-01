WITH cohort AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = p.subject_id
        AND di.hadm_id = a.hadm_id
        AND (di.icd_code LIKE 'E11%' OR di.icd_code = '250.00')
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = p.subject_id
        AND di.hadm_id = a.hadm_id
        AND (di.icd_code LIKE 'I50%' OR di.icd_code LIKE '428%')
    )
),

drug_flags AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    -- Metformin
    MAX(CASE WHEN LOWER(rx.drug) LIKE '%metformin%' AND rx.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS metformin_first72,
    MAX(CASE WHEN LOWER(rx.drug) LIKE '%metformin%' AND rx.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime THEN 1 ELSE 0 END) AS metformin_final48,

    -- Sulfonylurea
    MAX(CASE WHEN (LOWER(rx.drug) LIKE '%glyburide%' OR LOWER(rx.drug) LIKE '%glipizide%' OR LOWER(rx.drug) LIKE '%glimepiride%') AND rx.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS sulfonylurea_first72,
    MAX(CASE WHEN (LOWER(rx.drug) LIKE '%glyburide%' OR LOWER(rx.drug) LIKE '%glipizide%' OR LOWER(rx.drug) LIKE '%glimepiride%') AND rx.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime THEN 1 ELSE 0 END) AS sulfonylurea_final48,

    -- DPP4
    MAX(CASE WHEN (LOWER(rx.drug) LIKE '%sitagliptin%' OR LOWER(rx.drug) LIKE '%saxagliptin%' OR LOWER(rx.drug) LIKE '%linagliptin%' OR LOWER(rx.drug) LIKE '%alogliptin%') AND rx.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS dpp4_first72,
    MAX(CASE WHEN (LOWER(rx.drug) LIKE '%sitagliptin%' OR LOWER(rx.drug) LIKE '%saxagliptin%' OR LOWER(rx.drug) LIKE '%linagliptin%' OR LOWER(rx.drug) LIKE '%alogliptin%') AND rx.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime THEN 1 ELSE 0 END) AS dpp4_final48,

    -- SGLT2
    MAX(CASE WHEN (LOWER(rx.drug) LIKE '%canagliflozin%' OR LOWER(rx.drug) LIKE '%dapagliflozin%' OR LOWER(rx.drug) LIKE '%empagliflozin%') AND rx.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS sglt2_first72,
    MAX(CASE WHEN (LOWER(rx.drug) LIKE '%canagliflozin%' OR LOWER(rx.drug) LIKE '%dapagliflozin%' OR LOWER(rx.drug) LIKE '%empagliflozin%') AND rx.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime THEN 1 ELSE 0 END) AS sglt2_final48,

    -- TZD
    MAX(CASE WHEN (LOWER(rx.drug) LIKE '%pioglitazone%' OR LOWER(rx.drug) LIKE '%rosiglitazone%') AND rx.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS tzd_first72,
    MAX(CASE WHEN (LOWER(rx.drug) LIKE '%pioglitazone%' OR LOWER(rx.drug) LIKE '%rosiglitazone%') AND rx.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime THEN 1 ELSE 0 END) AS tzd_final48

  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    ON c.subject_id = rx.subject_id AND c.hadm_id = rx.hadm_id
  GROUP BY c.subject_id, c.hadm_id
)

SELECT
  'Metformin' AS drug_class,
  COUNT(*) AS total_patients,
  SUM(metformin_first72) AS count_first72,
  ROUND(100 * SUM(metformin_first72) / COUNT(*), 2) AS prevalence_first72,
  SUM(metformin_final48) AS count_final48,
  ROUND(100 * SUM(metformin_final48) / COUNT(*), 2) AS prevalence_final48,
  ROUND(100 * SUM(metformin_first72) / COUNT(*) - 100 * SUM(metformin_final48) / COUNT(*), 2) AS pp_difference
FROM drug_flags
UNION ALL
SELECT
  'Sulfonylurea' AS drug_class,
  COUNT(*) AS total_patients,
  SUM(sulfonylurea_first72) AS count_first72,
  ROUND(100 * SUM(sulfonylurea_first72) / COUNT(*), 2) AS prevalence_first72,
  SUM(sulfonylurea_final48) AS count_final48,
  ROUND(100 * SUM(sulfonylurea_final48) / COUNT(*), 2) AS prevalence_final48,
  ROUND(100 * SUM(sulfonylurea_first72) / COUNT(*) - 100 * SUM(sulfonylurea_final48) / COUNT(*), 2) AS pp_difference
FROM drug_flags
UNION ALL
SELECT
  'DPP4' AS drug_class,
  COUNT(*) AS total_patients,
  SUM(dpp4_first72) AS count_first72,
  ROUND(100 * SUM(dpp4_first72) / COUNT(*), 2) AS prevalence_first72,
  SUM(dpp4_final48) AS count_final48,
  ROUND(100 * SUM(dpp4_final48) / COUNT(*), 2) AS prevalence_final48,
  ROUND(100 * SUM(dpp4_first72) / COUNT(*) - 100 * SUM(dpp4_final48) / COUNT(*), 2) AS pp_difference
FROM drug_flags
UNION ALL
SELECT
  'SGLT2' AS drug_class,
  COUNT(*) AS total_patients,
  SUM(sglt2_first72) AS count_first72,
  ROUND(100 * SUM(sglt2_first72) / COUNT(*), 2) AS prevalence_first72,
  SUM(sglt2_final48) AS count_final48,
  ROUND(100 * SUM(sglt2_final48) / COUNT(*), 2) AS prevalence_final48,
  ROUND(100 * SUM(sglt2_first72) / COUNT(*) - 100 * SUM(sglt2_final48) / COUNT(*), 2) AS pp_difference
FROM drug_flags
UNION ALL
SELECT
  'TZD' AS drug_class,
  COUNT(*) AS total_patients,
  SUM(tzd_first72) AS count_first72,
  ROUND(100 * SUM(tzd_first72) / COUNT(*), 2) AS prevalence_first72,
  SUM(tzd_final48) AS count_final48,
  ROUND(100 * SUM(tzd_final48) / COUNT(*), 2) AS prevalence_final48,
  ROUND(100 * SUM(tzd_first72) / COUNT(*) - 100 * SUM(tzd_final48) / COUNT(*), 2) AS pp_difference
FROM drug_flags
ORDER BY drug_class;