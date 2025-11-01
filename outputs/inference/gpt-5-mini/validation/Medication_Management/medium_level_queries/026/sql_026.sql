WITH cohort AS (
  -- female patients age 38-48 (anchor_age), admissions that have BOTH diabetes and heart failure diagnoses
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND a.hadm_id IS NOT NULL
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
hadm_diag_flags AS (
  -- Determine which admissions have diabetes and heart failure diagnoses (text-based on d_icd_diagnoses.long_title)
  SELECT
    d.hadm_id,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%heart failure%' OR LOWER(dd.long_title) LIKE '%congestive heart%' THEN 1 ELSE 0 END) AS has_heart_failure
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE d.hadm_id IS NOT NULL
  GROUP BY d.hadm_id
),
cohort_hf_dm AS (
  -- Keep only admissions in cohort that have both diagnoses
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime
  FROM cohort c
  JOIN hadm_diag_flags hdf
    ON c.hadm_id = hdf.hadm_id
  WHERE hdf.has_diabetes = 1
    AND hdf.has_heart_failure = 1
),
meds_union AS (
  -- Union inpatient medication orders/dispenses from prescriptions and pharmacy during the admission
  SELECT
    pr.hadm_id,
    pr.starttime AS starttime,
    LOWER(COALESCE(pr.drug, '')) AS drug,
    LOWER(COALESCE(pr.route, '')) AS route,
    'prescriptions' AS source
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN cohort_hf_dm a
    ON pr.hadm_id = a.hadm_id
  WHERE pr.starttime IS NOT NULL
    -- ensure it starts within the admission window
    AND TIMESTAMP(pr.starttime) >= TIMESTAMP(a.admittime)
    AND TIMESTAMP(pr.starttime) <= TIMESTAMP(a.dischtime)

  UNION ALL

  SELECT
    ph.hadm_id,
    ph.starttime AS starttime,
    LOWER(COALESCE(ph.medication, '')) AS drug,
    LOWER(COALESCE(ph.route, '')) AS route,
    'pharmacy' AS source
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
  JOIN cohort_hf_dm a
    ON ph.hadm_id = a.hadm_id
  WHERE ph.starttime IS NOT NULL
    AND TIMESTAMP(ph.starttime) >= TIMESTAMP(a.admittime)
    AND TIMESTAMP(ph.starttime) <= TIMESTAMP(a.dischtime)
),
meds_classified AS (
  -- Classify each med record as insulin and/or oral antidiabetic
  SELECT
    m.hadm_id,
    TIMESTAMP(m.starttime) AS starttime,
    m.drug,
    m.route,
    -- Insulin detection: any drug text containing 'insulin'
    IF(REGEXP_CONTAINS(m.drug, 'insulin'), 1, 0) AS is_insulin,
    -- Oral detection: route indicates oral/PO OR drug matches a list of common oral/non-injectable antidiabetic agents
    IF(
      REGEXP_CONTAINS(m.route, '(oral|po)') OR
      REGEXP_CONTAINS(m.drug, '(metformin|glipizide|glyburide|glimepiride|gliclazide|glibenclamide|sitagliptin|linagliptin|saxagliptin|alogliptin|vildagliptin|repaglinide|nateglinide|pioglitazone|rosiglitazone|acarbose|miglitol|canagliflozin|dapagliflozin|empagliflozin|tolbutamide|tolazamide|chlorpropamide)'),
      1,
      0
    ) AS is_oral
  FROM meds_union m
),
meds_window_flags AS (
  -- For each admission, set flags indicating whether any insulin / any oral antidiabetic was started in the first 72h and in the final 72h
  SELECT
    a.hadm_id,
    -- first 72h window flags
    MAX(CASE WHEN TIMESTAMP(mc.starttime) >= TIMESTAMP(a.admittime)
                  AND TIMESTAMP(mc.starttime) <= TIMESTAMP_ADD(TIMESTAMP(a.admittime), INTERVAL 72 HOUR)
             AND mc.is_insulin = 1 THEN 1 ELSE 0 END) AS insulin_first72,
    MAX(CASE WHEN TIMESTAMP(mc.starttime) >= TIMESTAMP(a.admittime)
                  AND TIMESTAMP(mc.starttime) <= TIMESTAMP_ADD(TIMESTAMP(a.admittime), INTERVAL 72 HOUR)
             AND mc.is_oral = 1 THEN 1 ELSE 0 END) AS oral_first72,
    -- final 72h window flags
    MAX(CASE WHEN TIMESTAMP(mc.starttime) >= TIMESTAMP_SUB(TIMESTAMP(a.dischtime), INTERVAL 72 HOUR)
                  AND TIMESTAMP(mc.starttime) <= TIMESTAMP(a.dischtime)
             AND mc.is_insulin = 1 THEN 1 ELSE 0 END) AS insulin_final72,
    MAX(CASE WHEN TIMESTAMP(mc.starttime) >= TIMESTAMP_SUB(TIMESTAMP(a.dischtime), INTERVAL 72 HOUR)
                  AND TIMESTAMP(mc.starttime) <= TIMESTAMP(a.dischtime)
             AND mc.is_oral = 1 THEN 1 ELSE 0 END) AS oral_final72
  FROM cohort_hf_dm a
  LEFT JOIN meds_classified mc
    ON a.hadm_id = mc.hadm_id
  GROUP BY a.hadm_id
),
summary AS (
  SELECT
    COUNT(1) AS total_admissions,
    SUM(insulin_first72) AS n_insulin_first72,
    SUM(oral_first72) AS n_oral_first72,
    SUM(insulin_final72) AS n_insulin_final72,
    SUM(oral_final72) AS n_oral_final72
  FROM meds_window_flags
)
-- Final output: percentages for first vs final 72 hours
SELECT
  window_name,
  admissions AS total_admissions,
  started_insulin AS n_started_insulin,
  started_oral AS n_started_oral,
  ROUND(100.0 * SAFE_DIVIDE(started_insulin, admissions), 2) AS pct_started_insulin,
  ROUND(100.0 * SAFE_DIVIDE(started_oral, admissions), 2) AS pct_started_oral
FROM (
  SELECT
    'first_72h' AS window_name,
    s.total_admissions AS admissions,
    s.n_insulin_first72 AS started_insulin,
    s.n_oral_first72 AS started_oral
  FROM summary s

  UNION ALL

  SELECT
    'final_72h' AS window_name,
    s.total_admissions AS admissions,
    s.n_insulin_final72 AS started_insulin,
    s.n_oral_final72 AS started_oral
  FROM summary s
)
ORDER BY window_name;