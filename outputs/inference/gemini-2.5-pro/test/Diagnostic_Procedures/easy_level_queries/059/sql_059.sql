WITH
-- Step 1: Filter for male patients aged 76-86
filtered_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 76 AND 86
),

-- Step 2: Identify all ICD codes related to cardiac procedures
cardiac_codes AS (
  SELECT DISTINCT
    icd_code,
    icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE
    REGEXP_CONTAINS(LOWER(long_title), 'cardiac|heart|coronary|atrial|ventricular|valve|pericardial')
),

-- Step 3: Count the number of distinct cardiac procedures for each hospitalization of the filtered patients
proc_counts_per_hadm AS (
  SELECT
    p.hadm_id,
    COUNT(DISTINCT p.icd_code) AS num_distinct_cardiac_procs
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
  INNER JOIN
    filtered_patients AS fp
    ON p.subject_id = fp.subject_id
  INNER JOIN
    cardiac_codes AS cc
    ON p.icd_code = cc.icd_code AND p.icd_version = cc.icd_version
  GROUP BY
    p.hadm_id
)

-- Step 4: Calculate the Interquartile Range (IQR) of these counts
SELECT
  (
    APPROX_QUANTILES(num_distinct_cardiac_procs, 100)[OFFSET(75)] -
    APPROX_QUANTILES(num_distinct_cardiac_procs, 100)[OFFSET(25)]
  ) AS iqr_of_distinct_cardiac_procedures
FROM
  proc_counts_per_hadm;