WITH cohort AS (
  -- Step 1: Identify qualifying admissions
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    -- Age filter (anchor_age at anchor_year)
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 66 AND 76
      AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = a.hadm_id
          AND (
            -- Diabetes ICD-9: 250.*, ICD-10: E10-E14.*
            (d.icd_version = 9 AND LEFT(d.icd_code, 3) = '250')
            OR (d.icd_version = 10 AND LEFT(d.icd_code, 3) IN ('E10', 'E11', 'E12', 'E13', 'E14'))
          )
      )
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = a.hadm_id
          AND (
            -- Heart failure ICD-9: 428.*, ICD-10: I50.*
            (d.icd_version = 9 AND LEFT(d.icd_code, 3) = '428')
            OR (d.icd_version = 10 AND LEFT(d.icd_code, 3) = 'I50')
          )
      )
),
antidiabetic_admin AS (
  -- Step 2: Find antidiabetic drug administrations in EMAR
  SELECT
    e.subject_id,
    e.hadm_id,
    e.charttime,
    LOWER(ed.product_description) AS drug_desc,
    -- Drug class mapping
    CASE
      WHEN LOWER(ed.product_description) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(ed.product_description) LIKE '%metformin%' THEN 'Biguanide'
      WHEN LOWER(ed.product_description) LIKE '%glipizide%' OR LOWER(ed.product_description) LIKE '%glyburide%' OR LOWER(ed.product_description) LIKE '%glimepiride%' THEN 'Sulfonylurea'
      WHEN LOWER(ed.product_description) LIKE '%sitagliptin%' OR LOWER(ed.product_description) LIKE '%linagliptin%' OR LOWER(ed.product_description) LIKE '%saxagliptin%' OR LOWER(ed.product_description) LIKE '%alogliptin%' THEN 'DPP-4 inhibitor'
      WHEN LOWER(ed.product_description) LIKE '%canagliflozin%' OR LOWER(ed.product_description) LIKE '%dapagliflozin%' OR LOWER(ed.product_description) LIKE '%empagliflozin%' THEN 'SGLT2 inhibitor'
      WHEN LOWER(ed.product_description) LIKE '%liraglutide%' OR LOWER(ed.product_description) LIKE '%exenatide%' OR LOWER(ed.product_description) LIKE '%dulaglutide%' OR LOWER(ed.product_description) LIKE '%semaglutide%' THEN 'GLP-1 agonist'
      WHEN LOWER(ed.product_description) LIKE '%pioglitazone%' OR LOWER(ed.product_description) LIKE '%rosiglitazone%' THEN 'Thiazolidinedione'
      ELSE NULL
    END AS drug_class
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar` e
    JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
      ON e.subject_id = ed.subject_id
      AND e.emar_id = ed.emar_id
      AND e.emar_seq = ed.emar_seq
  WHERE
    -- Only actual administrations
    ed.administration_type = 'Given'
),
windowed_admin AS (
  -- Step 3: Assign administrations to time windows
  SELECT
    c.hadm_id,
    a.drug_class,
    -- First 72h window
    CASE WHEN a.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END AS in_first_72h,
    -- Final 24h window
    CASE WHEN a.charttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime THEN 1 ELSE 0 END AS in_final_24h
  FROM
    cohort c
    JOIN antidiabetic_admin a
      ON c.subject_id = a.subject_id
      AND c.hadm_id = a.hadm_id
  WHERE
    a.drug_class IS NOT NULL
),
adm_class_window AS (
  -- Step 4: For each admission, drug class, and window, flag if at least one admin occurred
  SELECT
    hadm_id,
    drug_class,
    MAX(in_first_72h) AS first_72h_admin,
    MAX(in_final_24h) AS final_24h_admin
  FROM
    windowed_admin
  GROUP BY
    hadm_id, drug_class
),
class_counts AS (
  -- Step 5: For each drug class, count admissions with admin in each window
  SELECT
    drug_class,
    SUM(first_72h_admin) AS n_first_72h,
    SUM(final_24h_admin) AS n_final_24h
  FROM
    adm_class_window
  GROUP BY
    drug_class
),
total_admissions AS (
  SELECT COUNT(*) AS n_adm FROM cohort
)
SELECT
  cc.drug_class,
  ROUND(100.0 * cc.n_first_72h / ta.n_adm, 1) AS pct_first_72h,
  ROUND(100.0 * cc.n_final_24h / ta.n_adm, 1) AS pct_final_24h
FROM
  class_counts cc
  CROSS JOIN total_admissions ta
ORDER BY
  cc.drug_class;