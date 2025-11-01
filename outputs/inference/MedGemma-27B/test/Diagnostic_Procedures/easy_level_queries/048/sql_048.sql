WITH PatientAgeGroup AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 52 AND 62
),
ProcedureCounts AS (
  SELECT
    a.subject_id,
    COUNT(DISTINCT p.icd_code) AS distinct_procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN PatientAgeGroup AS pag
    ON a.subject_id = pag.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
    ON a.hadm_id = p.hadm_id
  WHERE
    p.icd_code LIKE '33%' -- ICD-10 codes for valve repair/replacement start with 33
  GROUP BY
    a.subject_id
)
SELECT
  APPROX_QUANTILES(distinct_procedure_count, 4)[OFFSET(1)] AS iqr_q1,
  APPROX_QUANTILES(distinct_procedure_count, 4)[OFFSET(3)] AS iqr_q2
FROM ProcedureCounts;