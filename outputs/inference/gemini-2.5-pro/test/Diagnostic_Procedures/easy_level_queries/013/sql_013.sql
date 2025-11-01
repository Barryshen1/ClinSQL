WITH PatientCohort AS (
  -- Step 1: Identify hospital admissions for female patients aged 57-67
  SELECT
    p.subject_id,
    adm.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON p.subject_id = adm.subject_id
  WHERE
    p.gender = 'F'
    -- Calculate age at admission for accurate filtering
    AND (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year + p.anchor_age) BETWEEN 57 AND 67
),
ValveProcedureCodes AS (
  -- Step 2: Identify all ICD codes related to valve repair or replacement
  SELECT DISTINCT
    icd_code,
    icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE
    LOWER(long_title) LIKE '%valve replacement%'
    OR LOWER(long_title) LIKE '%valve repair%'
    OR LOWER(long_title) LIKE '%valvuloplasty%'
),
ProceduresPerHospitalization AS (
  -- Step 3: Count the number of distinct valve procedures for each relevant hospitalization
  SELECT
    pc.hadm_id,
    COUNT(DISTINCT proc.icd_code) AS num_distinct_procedures
  FROM
    PatientCohort AS pc
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    ON pc.hadm_id = proc.hadm_id
  INNER JOIN
    ValveProcedureCodes AS vpc
    ON proc.icd_code = vpc.icd_code
    AND proc.icd_version = vpc.icd_version
  GROUP BY
    pc.hadm_id
)
-- Step 4: Find the minimum count across all hospitalizations
SELECT
  MIN(num_distinct_procedures) AS min_distinct_valve_procedures
FROM
  ProceduresPerHospitalization;