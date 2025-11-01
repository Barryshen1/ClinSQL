WITH
-- Step 1: Identify all hospital admissions for patients with a COPD diagnosis.
copd_admissions AS (
  SELECT
    subject_id,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-9 codes for COPD: 491.x (chronic bronchitis), 492.x (emphysema), 496 (chronic airway obstruction)
    (icd_version = 9 AND (icd_code LIKE '491%' OR icd_code LIKE '492%' OR icd_code = '496'))
    -- ICD-10 codes for COPD: J41-J44
    OR (icd_version = 10 AND (icd_code LIKE 'J41%' OR icd_code LIKE 'J42%' OR icd_code LIKE 'J43%' OR icd_code LIKE 'J44%'))
  GROUP BY
    subject_id,
    hadm_id
),

-- Step 2: Filter for female patients and get their hospital admission time.
female_copd_admissions AS (
  SELECT
    copd.subject_id,
    copd.hadm_id,
    adm.admittime
  FROM
    copd_admissions AS copd
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON copd.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON copd.hadm_id = adm.hadm_id
  WHERE
    pat.gender = 'F'
),

-- Step 3: Get all serum creatinine measurements for these admissions within the first 24 hours.
creatinine_in_24h AS (
  SELECT
    fc_adm.hadm_id,
    le.valuenum
  FROM
    female_copd_admissions AS fc_adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON fc_adm.hadm_id = le.hadm_id
  WHERE
    -- itemid for Creatinine, Blood is 50912
    le.itemid = 50912
    AND le.valuenum IS NOT NULL -- We can only average numeric, non-null values
    -- Filter for the first 24 hours of the hospital admission
    AND le.charttime BETWEEN fc_adm.admittime AND TIMESTAMP_ADD(fc_adm.admittime, INTERVAL 24 HOUR)
),

-- Step 4: Calculate the average creatinine for each admission that had at least one measurement.
avg_creatinine_per_admission AS (
  SELECT
    hadm_id,
    AVG(valuenum) AS avg_creatinine
  FROM
    creatinine_in_24h
  GROUP BY
    hadm_id
)

-- Step 5: Calculate the 75th percentile of these average values.
SELECT
  APPROX_QUANTILES(avg_creatinine, 100)[OFFSET(75)] AS p75_avg_serum_creatinine
FROM
  avg_creatinine_per_admission;