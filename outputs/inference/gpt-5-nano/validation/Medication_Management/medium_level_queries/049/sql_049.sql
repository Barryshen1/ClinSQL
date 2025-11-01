with cohort AS (
  -- Filter for eligible inpatients
  SELECT a.hadm_id,
         a.admittime,
         a.dischtime,
         p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 66 AND 76
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, 'HOUR') >= 72
),

diag_flags AS (
  -- For each hadm_id, flag presence of diabetes and heart failure
  SELECT di.hadm_id,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%heart failure%' OR LOWER(dd.long_title) LIKE '%congestive heart failure%' THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  GROUP BY di.hadm_id
),

qualified_admissions AS (
  -- Admissions that satisfy all criteria: in cohort and have both diabetes and HF
  SELECT c.hadm_id, c.admittime, c.dischtime
  FROM cohort AS c
  JOIN diag_flags AS df ON df.hadm_id = c.hadm_id
  WHERE df.has_diabetes = 1
    AND df.has_hf = 1
),

totals AS (
  SELECT COUNT(DISTINCT hadm_id) AS total
  FROM qualified_admissions
),

-- First 72h: map drugs to antidiabetic classes (per prescription; no GROUP BY on alias)
first72 AS (
  SELECT
    CASE
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Biguanide'
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%' THEN 'Sulfonylurea'
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'TZD'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' THEN 'DPP-4 inhibitor'
      WHEN LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%ertugliflozin%' THEN 'SGLT2 inhibitor'
      WHEN LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%dulaglutide%' OR LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%semaglutide%' THEN 'GLP-1 receptor agonist'
      ELSE 'Other/Unknown'
    END AS class_label,
    qa.hadm_id
  FROM qualified_admissions qa
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON p.hadm_id = qa.hadm_id
  WHERE p.starttime < TIMESTAMP_ADD(qa.admittime, INTERVAL 72 HOUR)
    AND (p.stoptime IS NULL OR p.stoptime > qa.admittime)
),

final24 AS (
  SELECT
    CASE
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Biguanide'
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%' THEN 'Sulfonylurea'
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'TZD'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' THEN 'DPP-4 inhibitor'
      WHEN LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%ertugliflozin%' THEN 'SGLT2 inhibitor'
      WHEN LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%dulaglutide%' OR LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%semaglutide%' THEN 'GLP-1 receptor agonist'
      ELSE 'Other/Unknown'
    END AS class_label,
    qa.hadm_id
  FROM qualified_admissions qa
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON p.hadm_id = qa.hadm_id
  WHERE p.starttime < qa.dischtime
    AND (p.stoptime IS NULL OR p.stoptime > TIMESTAMP_SUB(qa.dischtime, INTERVAL 24 HOUR))
),

classes AS (
  -- All classes observed in either window
  SELECT class_label FROM first72
  UNION DISTINCT
  SELECT class_label FROM final24
)

SELECT
  c.class_label AS class_label,
  ROUND(100.0 * COALESCE(f.n, 0) / t.total, 2) AS first_72h_pct,
  ROUND(100.0 * COALESCE(fi.n, 0) / t.total, 2) AS final_24h_pct
FROM classes c
CROSS JOIN totals t
LEFT JOIN (
  SELECT class_label, COUNT(DISTINCT hadm_id) AS n
  FROM first72
  GROUP BY class_label
) f ON f.class_label = c.class_label
LEFT JOIN (
  SELECT class_label, COUNT(DISTINCT hadm_id) AS n
  FROM final24
  GROUP BY class_label
) fi ON fi.class_label = c.class_label
ORDER BY first_72h_pct DESC;