WITH PatientCohort AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
),
DiagnosisCohort AS (
  SELECT DISTINCT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND d.icd_code IN ('I63', 'I63.9', 'I63.5', 'I63.6', 'I63.8', 'I63.0', 'I63.1', 'I63.2', 'I63.3', 'I63.4') -- Hemorrhagic stroke codes
    AND d.icd_version = 10
),
ComorbidityCohort AS (
  SELECT DISTINCT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND d.icd_code = 'J44.1' -- COPD exacerbation code
    AND d.icd_version = 10
),
FinalCohort AS (
  SELECT
    dc.subject_id
  FROM
    DiagnosisCohort AS dc
  JOIN
    ComorbidityCohort AS cc ON dc.subject_id = cc.subject_id
)
SELECT
  PERCENTILE_CONT(0.25, a.los) AS iqr_25,
  PERCENTILE_CONT(0.75, a.los) AS iqr_75
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN
  FinalCohort AS fc ON a.subject_id = fc.subject_id
WHERE
  a.hospital_expire_flag = 0;