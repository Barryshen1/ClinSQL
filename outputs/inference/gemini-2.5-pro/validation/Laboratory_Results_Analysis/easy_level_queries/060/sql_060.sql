WITH pneumonia_admissions AS (
  -- Step 1: Identify all hospital admissions for male patients with a pneumonia diagnosis.
  SELECT DISTINCT
    adm.hadm_id,
    adm.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    pat.gender = 'M'
    AND LOWER(d_dx.long_title) LIKE '%pneumonia%'
),

first_day_glucose AS (
  -- Step 2: For this cohort, get all serum glucose lab values from the first 24 hours of admission.
  SELECT
    pna.hadm_id,
    le.valuenum
  FROM
    pneumonia_admissions AS pna
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON pna.hadm_id = le.hadm_id
  WHERE
    -- itemid for Glucose from d_labitems (50931: Glucose, 50809: Glucose)
    le.itemid IN (50931, 50809)
    AND le.valuenum IS NOT NULL
    AND le.charttime BETWEEN pna.admittime AND DATETIME_ADD(pna.admittime, INTERVAL 24 HOUR)
),

mean_glucose_per_admission AS (
  -- Step 3: Calculate the mean glucose for each admission.
  SELECT
    hadm_id,
    AVG(valuenum) AS mean_glucose
  FROM
    first_day_glucose
  GROUP BY
    hadm_id
)

-- Step 4: Calculate the 75th percentile of the mean glucose values across all admissions.
SELECT
  APPROX_QUANTILES(mean_glucose, 100)[OFFSET(75)] AS p75_mean_glucose
FROM
  mean_glucose_per_admission;