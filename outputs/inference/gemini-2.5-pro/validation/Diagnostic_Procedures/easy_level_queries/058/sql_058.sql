WITH
-- Step 1: Identify the cohort of female patients aged 86-96.
-- MIMIC-IV de-identifies ages >89 by binning them into a 91-year-old anchor age.
-- Therefore, the range 86-96 is effectively captured by 86-91 in the anchor_age column.
patient_cohort AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 91
),

-- Step 2: Get all hospital admissions for this patient cohort.
-- This is crucial to include admissions with zero MCS procedures in our analysis.
cohort_admissions AS (
  SELECT
    adm.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    patient_cohort AS cohort
    ON adm.subject_id = cohort.subject_id
),

-- Step 3: Identify all recorded mechanical circulatory support (MCS) procedures using ICD codes.
-- This list includes codes for IABP, VAD, ECMO, and other heart-assist devices.
mcs_procedures AS (
  SELECT
    proc.hadm_id,
    proc.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
  WHERE
    -- ICD-9 Codes
    proc.icd_code IN (
      '37.61', -- Insertion of intra-aortic balloon assist device
      '37.62', -- Implantation of heart assist system
      '37.65', -- Implantation of external heart assist system
      '37.66', -- Implantation of implantable pulsatile heart assist system
      '37.68', -- Insertion of percutaneous external heart assist device
      '39.65'  -- Extracorporeal circulation auxiliary to open heart surgery (often for ECMO)
    )
    OR
    -- ICD-10 Codes
    proc.icd_code IN (
      '5A02210', -- Assistance w/ cardiac output using balloon pump, percutaneous
      '5A0221D', -- Assistance w/ cardiac output using impeller pump, percutaneous
      '02HA0RS', -- Insertion of short-term external heart assist system into heart, open
      '02HA0RT', -- Insertion of tissue-substitute short-term external heart assist system into heart, open
      '5A15223', -- Extracorporeal membrane oxygenation, veno-arterial
      '5A1522G'  -- Extracorporeal membrane oxygenation, veno-venous, continuous
    )
),

-- Step 4: Count the number of *distinct* MCS procedures for each hospitalization in our cohort.
-- A LEFT JOIN ensures that hospitalizations with no MCS procedures are counted as 0.
proc_counts_per_hadm AS (
  SELECT
    ca.hadm_id,
    COUNT(DISTINCT mcs.icd_code) AS num_distinct_procedures
  FROM
    cohort_admissions AS ca
  LEFT JOIN
    mcs_procedures AS mcs
    ON ca.hadm_id = mcs.hadm_id
  GROUP BY
    ca.hadm_id
)

-- Step 5: Calculate the Interquartile Range (IQR) of the counts.
-- IQR is the difference between the 75th (Q3) and 25th (Q1) percentiles.
-- APPROX_QUANTILES(value, 4) returns an array: [min, Q1, median, Q3, max].
SELECT
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_of_distinct_mcs_procedures
FROM (
  SELECT
    APPROX_QUANTILES(num_distinct_procedures, 4) AS quantiles
  FROM
    proc_counts_per_hadm
);