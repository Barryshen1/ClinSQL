WITH
  -- Step 1: Identify the base cohort of female patients aged 50-60 and their hospital admissions.
  patient_cohort AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 50 AND 60
  ),
  -- Step 2 & 3: Filter for admissions with an ACS diagnosis and classify it as Primary or Secondary.
  acs_admissions AS (
    SELECT
      pc.hadm_id,
      CASE
        WHEN MIN(diag.seq_num) = 1
        THEN 'Primary'
        ELSE 'Secondary'
      END AS diagnosis_type
    FROM
      patient_cohort AS pc
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
      ON pc.hadm_id = diag.hadm_id
    WHERE
      -- ICD-9 codes for ACS (AMI: 410.*, Unstable Angina: 411.1)
      (
        diag.icd_version = 9 AND (diag.icd_code LIKE '410%' OR diag.icd_code = '4111')
      )
      OR
      -- ICD-10 codes for ACS (Unstable Angina: I20.0, AMI: I21.*, I22.*)
      (
        diag.icd_version = 10
        AND (diag.icd_code = 'I200' OR diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%')
      )
    GROUP BY
      pc.hadm_id
  ),
  -- Step 4 & 5: Calculate LOS, create LOS category, and count procedures per admission.
  procedure_counts AS (
    SELECT
      aa.hadm_id,
      aa.diagnosis_type,
      CASE
        WHEN DATETIME_DIFF(pc.dischtime, pc.admittime, DAY) BETWEEN 1 AND 4
        THEN '1-4 days'
        WHEN DATETIME_DIFF(pc.dischtime, pc.admittime, DAY) BETWEEN 5 AND 8
        THEN '5-8 days'
        ELSE NULL
      END AS los_category,
      -- Count procedures for the admission. LEFT JOIN ensures we count 0 for admissions with no procedures.
      COUNT(proc.icd_code) AS procedure_count
    FROM
      acs_admissions AS aa
    INNER JOIN
      patient_cohort AS pc
      ON aa.hadm_id = pc.hadm_id
    LEFT JOIN
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
      ON aa.hadm_id = proc.hadm_id
    WHERE
      pc.dischtime IS NOT NULL AND pc.admittime IS NOT NULL
    GROUP BY
      aa.hadm_id,
      aa.diagnosis_type,
      pc.admittime,
      pc.dischtime
  )
-- Step 6: Aggregate the procedure counts to calculate p25, p50, p75 for each stratum.
SELECT
  los_category,
  diagnosis_type,
  -- APPROX_QUANTILES with 4 intervals returns an array of 5 values: [min, p25, p50, p75, max].
  -- We extract p25, p50, and p75 using their array offsets (1, 2, and 3).
  APPROX_QUANTILES(procedure_count, 4) [
  OFFSET
    (1)] AS p25_procedures,
  APPROX_QUANTILES(procedure_count, 4) [
  OFFSET
    (2)] AS p50_procedures,
  APPROX_QUANTILES(procedure_count, 4) [
  OFFSET
    (3)] AS p75_procedures
FROM
  procedure_counts
WHERE
  los_category IS NOT NULL -- Filter to only the LOS bins we care about
GROUP BY
  los_category,
  diagnosis_type
ORDER BY
  los_category,
  diagnosis_type;