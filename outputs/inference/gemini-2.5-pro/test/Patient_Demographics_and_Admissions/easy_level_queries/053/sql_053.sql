WITH

-- Step 1: Create a table of all admissions with the next admission time for each patient
AdmissionSequences AS (
  SELECT
    subject_id,
    hadm_id,
    dischtime,
    LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- Step 2: Identify the index hospital admissions that meet the cohort criteria
IndexAdmissions AS (
  SELECT DISTINCT
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON a.hadm_id = dx.hadm_id
  WHERE
    -- Condition 1: Patient is female
    p.gender = 'F'
    -- Condition 2: Patient age at admission is between 52 and 62
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 52 AND 62
    -- Condition 3: Diagnosis of Acute Kidney Injury (AKI) using either ICD-9 or ICD-10
    AND (
      (dx.icd_version = 9 AND dx.icd_code LIKE '584%')
      OR (dx.icd_version = 10 AND dx.icd_code LIKE 'N17%')
    )
),

-- Step 3: For each index admission, determine if it resulted in a 30-day readmission
ReadmissionFlags AS (
  SELECT
    ia.hadm_id,
    -- Flag is 1 if the next admission is within 30 days of discharge, 0 otherwise
    CASE
      WHEN DATETIME_DIFF(seq.next_admittime, seq.dischtime, DAY) <= 30 THEN 1
      ELSE 0
    END AS is_readmitted_in_30_days
  FROM
    IndexAdmissions AS ia
  INNER JOIN
    AdmissionSequences AS seq
    ON ia.hadm_id = seq.hadm_id
)

-- Step 4: Calculate the population standard deviation of the 30-day readmission flag
SELECT
  STDDEV_POP(is_readmitted_in_30_days) AS stddev_30_day_readmission
FROM
  ReadmissionFlags;