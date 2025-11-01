WITH PatientCohort AS (
  -- Step 1: Identify female patients aged 64-74
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 64 AND 74
),
PatientProcedureCounts AS (
  -- Step 2: Count diagnostic cardiac catheterization procedures for each patient in the cohort
  SELECT
    proc.subject_id,
    COUNT(*) AS num_procedures
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
  INNER JOIN
    PatientCohort AS pc
    ON proc.subject_id = pc.subject_id
  WHERE
    -- Filter for ICD-9 codes for diagnostic cardiac catheterization.
    -- Codes are stored without decimals.
    -- 3721: Left heart cardiac catheterization
    -- 3722: Right heart cardiac catheterization
    -- 3723: Right and left heart cardiac catheterization
    proc.icd_version = 9
    AND proc.icd_code IN ('3721', '3722', '3723')
  GROUP BY
    proc.subject_id
)
-- Step 3: Find the minimum count among all patients who had the procedure
SELECT
  MIN(num_procedures) AS min_procedures_per_patient
FROM
  PatientProcedureCounts;