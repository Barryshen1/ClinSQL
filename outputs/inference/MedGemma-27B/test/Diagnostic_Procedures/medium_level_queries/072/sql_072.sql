WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age = 57
    AND gender = 'F'
),
Diagnosis AS (
  SELECT
    p.subject_id,
    d.hadm_id,
    d.icd_code,
    d.seq_num
  FROM
    PatientInfo AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON p.subject_id = d.subject_id
  WHERE
    d.icd_code = 'K85' -- Acute pancreatitis ICD-10 code
    AND d.seq_num = 1 -- Primary diagnosis
),
AdmissionInfo AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    d.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN Diagnosis AS d
      ON a.hadm_id = d.hadm_id
),
ProcedureInfo AS (
  SELECT
    a.hadm_id,
    pr.icd_code,
    pr.seq_num
  FROM
    AdmissionInfo AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pr
      ON a.hadm_id = pr.hadm_id
),
ProcedureCount AS (
  SELECT
    a.hadm_id,
    COUNT(pr.icd_code) AS procedure_count,
    -- Calculate length of stay
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    AdmissionInfo AS a
    JOIN ProcedureInfo AS pr
      ON a.hadm_id = pr.hadm_id
  GROUP BY
    a.hadm_id,
    a.dischtime,
    a.admittime
),
ProcedureCountStratified AS (
  SELECT
    procedure_count,
    los,
    CASE
      WHEN seq_num = 1
      THEN 'Primary'
      ELSE 'Secondary'
    END AS procedure_type
  FROM
    ProcedureCount AS pc
    JOIN ProcedureInfo AS pi
      ON pc.hadm_id = pi.hadm_id
)
SELECT
  CASE
    WHEN los BETWEEN 1 AND 4
    THEN '1-4 days'
    WHEN los BETWEEN 5 AND 8
    THEN '5-8 days'
    ELSE 'Other'
  END AS los_category,
  procedure_type,
  COUNT(procedure_count) AS total_admissions,
  AVG(procedure_count) AS mean_procedures,
  MIN(procedure_count) AS min_procedures,
  MAX(procedure_count) AS max_procedures
FROM
  ProcedureCountStratified
WHERE
  los BETWEEN 1 AND 8
GROUP BY
  los_category,
  procedure_type
ORDER BY
  los_category,
  procedure_type;