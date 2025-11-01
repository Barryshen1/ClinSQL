WITH cohort AS (
  -- Step 1: Identify male patients aged 36–46 with T2DM and heart failure
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE d.icd_code IN ('25000', 'E119') -- T2DM
    )
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE d.icd_code IN ('4280', 'I509') -- Heart failure
    )
),

-- Step 2: Map prescriptions to antidiabetic classes
drug_class_map AS (
  SELECT
    drug,
    CASE
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'Biguanide'
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%' THEN 'Sulfonylurea'
      WHEN LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%saxagliptin%' THEN 'DPP-4 Inhibitor'
      WHEN LOWER(drug) LIKE '%empagliflozin%' OR LOWER(drug) LIKE '%dapagliflozin%' THEN 'SGLT-2 Inhibitor'
      WHEN LOWER(drug) LIKE '%pioglitazone%' THEN 'Thiazolidinedione'
      WHEN LOWER(drug) LIKE '%liraglutide%' OR LOWER(drug) LIKE '%semaglutide%' THEN 'GLP-1 Agonist'
      ELSE 'Other'
    END AS drug_class
  FROM
    physionet-data.mimiciv_3_1_hosp.prescriptions
  WHERE
    LOWER(drug) LIKE '%insulin%'
    OR LOWER(drug) LIKE '%metformin%'
    OR LOWER(drug) LIKE '%glipizide%'
    OR LOWER(drug) LIKE '%glyburide%'
    OR LOWER(drug) LIKE '%sitagliptin%'
    OR LOWER(drug) LIKE '%saxagliptin%'
    OR LOWER(drug) LIKE '%empagliflozin%'
    OR LOWER(drug) LIKE '%dapagliflozin%'
    OR LOWER(drug) LIKE '%pioglitazone%'
    OR LOWER(drug) LIKE '%liraglutide%'
    OR LOWER(drug) LIKE '%semaglutide%'
),

-- Step 3: Identify prescriptions within time windows
prescriptions_with_window AS (
  SELECT
    p.hadm_id,
    p.drug,
    p.starttime,
    c.admittime,
    c.dischtime,
    dcm.drug_class,
    CASE
      WHEN p.starttime BETWEEN c.admittime AND c.admittime + INTERVAL 12 HOUR THEN 'first_12h'
      WHEN p.starttime BETWEEN c.dischtime - INTERVAL 48 HOUR AND c.dischtime THEN 'final_48h'
    END AS time_window
  FROM
    physionet-data.mimiciv_3_1_hosp.prescriptions p
  JOIN
    cohort c ON p.hadm_id = c.hadm_id
  JOIN
    drug_class_map dcm ON p.drug = dcm.drug
  WHERE
    p.starttime IS NOT NULL
    AND p.drug_type = 'MAIN'
),

-- Step 4: Count initiations per window per class
initiations AS (
  SELECT
    drug_class,
    time_window,
    COUNT(DISTINCT hadm_id) AS initiated_admissions
  FROM
    prescriptions_with_window
  WHERE
    time_window IN ('first_12h', 'final_48h')
  GROUP BY
    drug_class, time_window
),

-- Step 5: Total admissions in cohort
total_admissions AS (
  SELECT COUNT(DISTINCT hadm_id) AS total FROM cohort
),

-- Step 6: Compute initiation rates
rates AS (
  SELECT
    i.drug_class,
    i.time_window,
    i.initiated_admissions,
    t.total,
    ROUND(100.0 * i.initiated_admissions / t.total, 2) AS initiation_rate_pct
  FROM
    initiations i
  CROSS JOIN
    total_admissions t
),

-- Step 7: Pivot and compute net change
pivoted AS (
  SELECT
    drug_class,
    MAX(CASE WHEN time_window = 'first_12h' THEN initiation_rate_pct ELSE 0 END) AS first_12h_pct,
    MAX(CASE WHEN time_window = 'final_48h' THEN initiation_rate_pct ELSE 0 END) AS final_48h_pct
  FROM
    rates
  GROUP BY
    drug_class
)

-- Final output
SELECT
  drug_class,
  first_12h_pct,
  final_48h_pct,
  ROUND(final_48h_pct - first_12h_pct, 2) AS net_change_pp
FROM
  pivoted
ORDER BY
  drug_class;