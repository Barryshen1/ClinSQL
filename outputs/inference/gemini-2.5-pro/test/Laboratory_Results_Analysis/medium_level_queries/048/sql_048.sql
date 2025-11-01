WITH ami_admissions AS (
  -- Step 1: Identify hospital admissions for female patients aged 55-65 with an AMI diagnosis.
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
    AND (
      -- Acute Myocardial Infarction ICD-9 codes
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      -- Acute Myocardial Infarction ICD-10 codes
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
    )
),
first_troponin AS (
  -- Step 2: Find the first high-sensitivity troponin T measurement for each of these admissions.
  SELECT
    ami.subject_id,
    ami.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY ami.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM
    ami_admissions AS ami
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON ami.hadm_id = le.hadm_id
  WHERE
    le.itemid = 52598 -- Troponin T, High Sensitivity
    AND le.valuenum IS NOT NULL
)
-- Step 3: Filter for admissions where the first troponin is > 0.01 ng/mL
-- and calculate the final summary statistics.
SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(valuenum) AS hs_tnt_mean,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS hs_tnt_median,
  (
    APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)]
  ) AS hs_tnt_iqr
FROM
  first_troponin
WHERE
  rn = 1
  AND valuenum > 0.01;