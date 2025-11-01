WITH PatientCohort AS (
  SELECT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M' AND p.anchor_age >= 86 AND p.anchor_age <= 96
), DiagnosisCohort AS (
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.subject_id IN (
      SELECT
        subject_id
      FROM PatientCohort
    )
    AND d.icd_code IN ('571.8', '571.9', '578.0', '578.1', '578.2', '578.3', '578.4', '578.5', '578.6', '578.7', '578.8', '578.9') -- UGIB codes
), ComorbidityCohort AS (
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.subject_id IN (
      SELECT
        subject_id
      FROM DiagnosisCohort
    )
    AND d.icd_code IN ('491.21', '491.22', '491.29', '491.8', '491.9', '492.81', '492.82', '492.89', '493.11', '493.12', '493.19', '493.21', '493.22', '493.29', '493.31', '493.32', '493.39', '494.0', '494.1', '494.2', '494.3', '494.4', '494.5', '494.6', '494.7', '494.8', '494.9', '496.0', '496.1', '496.2', '496.3', '496.4', '496.5', '496.6', '496.7', '496.8', '496.9') -- COPD codes
), FinalCohort AS (
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN ComorbidityCohort AS c
    ON p.subject_id = c.subject_id
), HospitalStays AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS length_of_stay
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM FinalCohort
    )
    AND a.dischtime IS NOT NULL
)
SELECT
  AVG(length_of_stay)
FROM HospitalStays;