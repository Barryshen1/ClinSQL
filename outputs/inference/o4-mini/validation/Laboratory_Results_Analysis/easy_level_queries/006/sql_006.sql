WITH cohort AS (
  -- Step 1: Identify all hospital admissions of 50-year-old females with a COPD diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.subject_id = d.subject_id
      AND a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
      ON d.icd_code = di.icd_code
      AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age = 50
    AND LOWER(di.long_title) LIKE '%copd%'
),

sodium_labs AS (
  -- Step 2: Pull all serum sodium lab results for the cohort during their hospital stay
  SELECT
    c.hadm_id,
    le.valuenum
  FROM
    cohort AS c
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      ON c.subject_id = le.subject_id
      AND c.hadm_id = le.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
      ON le.itemid = li.itemid
  WHERE
    li.label LIKE '%Sodium%'
    AND li.fluid = 'Blood'
    AND le.valuenum IS NOT NULL
    AND le.charttime BETWEEN c.admittime AND c.dischtime
),

nadir_per_admission AS (
  -- Step 3: For each admission, compute the nadir (minimum) sodium
  SELECT
    hadm_id,
    MIN(valuenum) AS nadir_sodium
  FROM
    sodium_labs
  GROUP BY
    hadm_id
)

-- Step 4: Compute the standard deviation of these nadir values across the cohort
SELECT
  STDDEV_SAMP(nadir_sodium) AS sd_nadir_serum_sodium
FROM
  nadir_per_admission;