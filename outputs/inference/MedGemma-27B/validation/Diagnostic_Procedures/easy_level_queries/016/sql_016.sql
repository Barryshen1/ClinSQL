WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age >= 75 AND anchor_age <= 85
), ProcedureCounts AS (
  SELECT
    a.subject_id,
    COUNT(DISTINCT p.icd_code) AS distinct_procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
    ON a.hadm_id = p.hadm_id
  JOIN PatientInfo AS pi
    ON a.subject_id = pi.subject_id
  WHERE
    p.icd_code LIKE '93%' -- ECG/Telemetry procedures start with 93 in ICD-9
  GROUP BY
    a.subject_id
)
SELECT
  PERCENTILE_CONT(distinct_procedure_count, 0.75) AS percentile_75
FROM ProcedureCounts;