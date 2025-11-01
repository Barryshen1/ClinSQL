WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250.%') OR
          (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428.%') OR
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),

drug_mappings AS (
  SELECT
    hadm_id,
    LOWER(drug) AS drug_name,
    starttime,
    stoptime,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(drug), r'insulin') THEN 'Insulin'
      WHEN REGEXP_CONTAINS(LOWER(drug), r'metformin') THEN 'Metformin'
      WHEN REGEXP_CONTAINS(LOWER(drug), r'glipizide|glyburide|glimepiride') THEN 'Sulfonylurea'
      WHEN REGEXP_CONTAINS(LOWER(drug), r'sitagliptin|saxagliptin|linagliptin|alogliptin') THEN 'DPP-4'
      WHEN REGEXP_CONTAINS(LOWER(drug), r'empagliflozin|dapagliflozin|canagliflozin|ertugliflozin') THEN 'SGLT2'
      WHEN REGEXP_CONTAINS(LOWER(drug), r'liraglutide|semaglutide|exenatide|dulaglutide|lixisenatide') THEN 'GLP-1'
      WHEN REGEXP_CONTAINS(LOWER(drug), r'pioglitazone|rosiglitazone') THEN 'TZD'
      ELSE NULL
    END AS drug_class
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    hadm_id IN (SELECT hadm_id FROM cohort)
),

first_72h_drugs AS (
  SELECT DISTINCT
    dm.hadm_id,
    dm.drug_class
  FROM
    drug_mappings dm
  JOIN
    cohort c ON dm.hadm_id = c.hadm_id
  WHERE
    dm.drug_class IS NOT NULL
    AND dm.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND (dm.stoptime IS NULL OR dm.stoptime >= c.admittime)
),

last_72h_drugs AS (
  SELECT DISTINCT
    dm.hadm_id,
    dm.drug_class
  FROM
    drug_mappings dm
  JOIN
    cohort c ON dm.hadm_id = c.hadm_id
  WHERE
    dm.drug_class IS NOT NULL
    AND dm.starttime <= c.dischtime
    AND (dm.stoptime IS NULL OR dm.stoptime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR))
),

drug_class_list AS (
  SELECT 'Insulin' AS drug_class UNION ALL
  SELECT 'Metformin' UNION ALL
  SELECT 'Sulfonylurea' UNION ALL
  SELECT 'DPP-4' UNION ALL
  SELECT 'SGLT2' UNION ALL
  SELECT 'GLP-1' UNION ALL
  SELECT 'TZD'
),

first_72h_counts AS (
  SELECT
    dcl.drug_class,
    COUNT(DISTINCT f72.hadm_id) AS cnt
  FROM
    drug_class_list dcl
  LEFT JOIN
    first_72h_drugs f72 ON dcl.drug_class = f72.drug_class
  GROUP BY
    dcl.drug_class
),

last_72h_counts AS (
  SELECT
    dcl.drug_class,
    COUNT(DISTINCT l72.hadm_id) AS cnt
  FROM
    drug_class_list dcl
  LEFT JOIN
    last_72h_drugs l72 ON dcl.drug_class = l72.drug_class
  GROUP BY
    dcl.drug_class
),

total_admissions AS (
  SELECT COUNT(DISTINCT hadm_id) AS total FROM cohort
)

SELECT
  f72.drug_class,
  ROUND(100 * COALESCE(f72.cnt, 0) / t.total, 2) AS percent_first_72h,
  ROUND(100 * COALESCE(l72.cnt, 0) / t.total, 2) AS percent_last_72h
FROM
  first_72h_counts f72
JOIN
  last_72h_counts l72 ON f72.drug_class = l72.drug_class
CROSS JOIN
  total_admissions t
ORDER BY
  f72.drug_class;