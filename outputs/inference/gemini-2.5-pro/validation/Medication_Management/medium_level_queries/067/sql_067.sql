WITH
-- Step 1: Pre-aggregate diagnoses to identify relevant hospital admissions
cohort_diagnoses AS (
  SELECT
    dx.hadm_id,
    MAX(CASE WHEN LOWER(d_dx.long_title) LIKE '%diabetes mellitus%' THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN LOWER(d_dx.long_title) LIKE '%acute%' AND LOWER(d_dx.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END) AS has_acute_hf
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  GROUP BY
    dx.hadm_id
),

-- Step 2: Define the final patient cohort based on demographics and diagnoses
cohort AS (
  SELECT
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    cohort_diagnoses AS cd
    ON adm.hadm_id = cd.hadm_id
  WHERE
    pat.gender = 'M'
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 64 AND 74
    AND cd.has_diabetes = 1
    AND cd.has_acute_hf = 1
),

-- Get total number of patients for the denominator
total_cohort_patients AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_count FROM cohort
),

-- Step 3: Identify and classify antidiabetic medication prescriptions for the cohort
antidiabetic_meds AS (
  SELECT
    pres.hadm_id,
    pres.starttime,
    CASE
      WHEN LOWER(pres.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(pres.drug) LIKE '%metformin%' THEN 'Metformin'
      -- Sulfonylureas
      WHEN LOWER(pres.drug) LIKE '%glipizide%' OR LOWER(pres.drug) LIKE '%glyburide%' OR LOWER(pres.drug) LIKE '%glimepiride%' THEN 'Sulfonylureas'
      -- DPP-4 inhibitors
      WHEN LOWER(pres.drug) LIKE '%sitagliptin%' OR LOWER(pres.drug) LIKE '%saxagliptin%' OR LOWER(pres.drug) LIKE '%linagliptin%' OR LOWER(pres.drug) LIKE '%alogliptin%' THEN 'DPP-4 inhibitors'
      -- SGLT2 inhibitors
      WHEN LOWER(pres.drug) LIKE '%gliflozin%' THEN 'SGLT2 inhibitors'
      -- GLP-1 agonists
      WHEN LOWER(pres.drug) LIKE '%glutide%' OR LOWER(pres.drug) LIKE '%exenatide%' THEN 'GLP-1 agonists'
      -- Thiazolidinediones (TZDs)
      WHEN LOWER(pres.drug) LIKE '%glitazone%' THEN 'Thiazolidinediones (TZDs)'
      ELSE NULL
    END AS drug_class
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
  WHERE
    pres.hadm_id IN (SELECT hadm_id FROM cohort)
),

-- Step 4: Find the first administration (initiation) time for each drug class per patient
first_admin_per_class AS (
  SELECT
    hadm_id,
    drug_class,
    MIN(starttime) AS first_admin_time
  FROM
    antidiabetic_meds
  WHERE
    drug_class IS NOT NULL
  GROUP BY
    hadm_id,
    drug_class
),

-- Step 5: Categorize each initiation into the 'First 12h' or 'Final 48h' windows
categorized_initiations AS (
  SELECT
    fa.hadm_id,
    fa.drug_class,
    CASE
      -- Check if initiation time is within the first 12 hours of admission
      WHEN fa.first_admin_time <= TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR)
      THEN 'First 12h'
      -- Check if initiation time is within the final 48 hours of admission
      WHEN fa.first_admin_time >= TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND fa.first_admin_time <= c.dischtime
      THEN 'Final 48h'
      ELSE NULL -- Ignored if not in these windows
    END AS initiation_window
  FROM
    first_admin_per_class AS fa
  INNER JOIN
    cohort AS c
    ON fa.hadm_id = c.hadm_id
)

-- Final Step: Aggregate results and calculate percentages
SELECT
  ci.drug_class,
  ci.initiation_window,
  COUNT(DISTINCT ci.hadm_id) AS num_patients_initiated,
  tcp.total_count AS total_cohort_size,
  ROUND(COUNT(DISTINCT ci.hadm_id) * 100.0 / tcp.total_count, 2) AS initiation_percentage
FROM
  categorized_initiations AS ci,
  total_cohort_patients AS tcp
WHERE
  ci.initiation_window IS NOT NULL
GROUP BY
  ci.drug_class,
  ci.initiation_window,
  tcp.total_count
ORDER BY
  ci.drug_class,
  ci.initiation_window;