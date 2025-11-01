WITH PatientAgeGroup AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 81 AND 91
),
ProcedureCodes AS (
  SELECT
    proc.subject_id,
    proc.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON proc.hadm_id = adm.hadm_id
  JOIN PatientAgeGroup AS pag
    ON proc.subject_id = pag.subject_id
  WHERE
    proc.icd_code LIKE '930%' -- ECG/telemetry codes start with 930
),
PatientProcedureCounts AS (
  SELECT
    subject_id,
    COUNT(DISTINCT icd_code) AS distinct_procedure_count
  FROM ProcedureCodes
  GROUP BY
    subject_id
)
SELECT
  STDDEV(distinct_procedure_count)
FROM PatientProcedureCounts;