WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON pat.subject_id = a.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 81 AND 91
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%')
          OR (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),
first72 AS (
  SELECT
    c.hadm_id,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 1 ELSE 0 END) AS metformin_first72,
    MAX(CASE WHEN
      LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR
      LOWER(pr.drug) LIKE '%glimepiride%' OR LOWER(pr.drug) LIKE '%chlorpropamide%' OR
      LOWER(pr.drug) LIKE '%tolbutamide%'
      THEN 1 ELSE 0 END) AS sulfonylurea_first72,
    MAX(CASE WHEN
      LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR
      LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%'
      THEN 1 ELSE 0 END) AS dpp4_first72,
    MAX(CASE WHEN
      LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR
      LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%ertugliflozin%'
      THEN 1 ELSE 0 END) AS sglt2_first72,
    MAX(CASE WHEN
      LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%'
      THEN 1 ELSE 0 END) AS tzd_first72
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pr.subject_id = c.subject_id
   AND pr.hadm_id = c.hadm_id
   AND pr.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
   AND (pr.stoptime IS NULL OR pr.stoptime >= c.admittime)
  GROUP BY c.hadm_id
),
final48 AS (
  SELECT
    c.hadm_id,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 1 ELSE 0 END) AS metformin_final48,
    MAX(CASE WHEN
      LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR
      LOWER(pr.drug) LIKE '%glimepiride%' OR LOWER(pr.drug) LIKE '%chlorpropamide%' OR
      LOWER(pr.drug) LIKE '%tolbutamide%'
      THEN 1 ELSE 0 END) AS sulfonylurea_final48,
    MAX(CASE WHEN
      LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR
      LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%'
      THEN 1 ELSE 0 END) AS dpp4_final48,
    MAX(CASE WHEN
      LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR
      LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%ertugliflozin%'
      THEN 1 ELSE 0 END) AS sglt2_final48,
    MAX(CASE WHEN
      LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%'
      THEN 1 ELSE 0 END) AS tzd_final48
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pr.subject_id = c.subject_id
   AND pr.hadm_id = c.hadm_id
   AND pr.starttime <= c.dischtime
   AND (pr.stoptime IS NULL OR pr.stoptime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR))
  GROUP BY c.hadm_id
)

SELECT
  'Metformin' AS class,
  ROUND(100.0 * AVG(IF(f72.metformin_first72 = 1, 1, 0))) AS prevalence_first72,
  ROUND(100.0 * AVG(IF(f48.metformin_final48 = 1, 1, 0))) AS prevalence_final48,
  ROUND(100.0 * ABS( AVG(IF(f48.metformin_final48 = 1, 1, 0)) - AVG(IF(f72.metformin_first72 = 1, 1, 0)) )) AS abs_diff_pp
FROM cohort c
LEFT JOIN first72 f72 ON f72.hadm_id = c.hadm_id
LEFT JOIN final48 f48 ON f48.hadm_id = c.hadm_id

UNION ALL
SELECT
  'Sulfonylurea' AS class,
  ROUND(100.0 * AVG(IF(f72.sulfonylurea_first72 = 1, 1, 0))) AS prevalence_first72,
  ROUND(100.0 * AVG(IF(f48.sulfonylurea_final48 = 1, 1, 0))) AS prevalence_final48,
  ROUND(100.0 * ABS( AVG(IF(f48.sulfonylurea_final48 = 1, 1, 0)) - AVG(IF(f72.sulfonylurea_first72 = 1, 1, 0)) )) AS abs_diff_pp
FROM cohort c
LEFT JOIN first72 f72 ON f72.hadm_id = c.hadm_id
LEFT JOIN final48 f48 ON f48.hadm_id = c.hadm_id

UNION ALL
SELECT
  'DPP-4 inhibitors' AS class,
  ROUND(100.0 * AVG(IF(f72.dpp4_first72 = 1, 1, 0))) AS prevalence_first72,
  ROUND(100.0 * AVG(IF(f48.dpp4_final48 = 1, 1, 0))) AS prevalence_final48,
  ROUND(100.0 * ABS( AVG(IF(f48.dpp4_final48 = 1, 1, 0)) - AVG(IF(f72.dpp4_first72 = 1, 1, 0)) )) AS abs_diff_pp
FROM cohort c
LEFT JOIN first72 f72 ON f72.hadm_id = c.hadm_id
LEFT JOIN final48 f48 ON f48.hadm_id = c.hadm_id

UNION ALL
SELECT
  'SGLT-2 inhibitors' AS class,
  ROUND(100.0 * AVG(IF(f72.sglt2_first72 = 1, 1, 0))) AS prevalence_first72,
  ROUND(100.0 * AVG(IF(f48.sglt2_final48 = 1, 1, 0))) AS prevalence_final48,
  ROUND(100.0 * ABS( AVG(IF(f48.sglt2_final48 = 1, 1, 0)) - AVG(IF(f72.sglt2_first72 = 1, 1, 0)) )) AS abs_diff_pp
FROM cohort c
LEFT JOIN first72 f72 ON f72.hadm_id = c.hadm_id
LEFT JOIN final48 f48 ON f48.hadm_id = c.hadm_id

UNION ALL
SELECT
  'TZD' AS class,
  ROUND(100.0 * AVG(IF(f72.tzd_first72 = 1, 1, 0))) AS prevalence_first72,
  ROUND(100.0 * AVG(IF(f48.tzd_final48 = 1, 1, 0))) AS prevalence_final48,
  ROUND(100.0 * ABS( AVG(IF(f48.tzd_final48 = 1, 1, 0)) - AVG(IF(f72.tzd_first72 = 1, 1, 0)) )) AS abs_diff_pp
FROM cohort c
LEFT JOIN first72 f72 ON f72.hadm_id = c.hadm_id
LEFT JOIN final48 f48 ON f48.hadm_id = c.hadm_id;