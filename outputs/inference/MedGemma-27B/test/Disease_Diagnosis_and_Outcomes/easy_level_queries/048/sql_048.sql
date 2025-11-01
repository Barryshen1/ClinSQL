WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 67 AND 77
), PatientDiagnosis AS (
  SELECT
    p.subject_id,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 67 AND 77 AND d.icd_code LIKE 'A41%'
), AdmissionInfo AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.dischtime,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    PatientDiagnosis AS pd
    ON a.subject_id = pd.subject_id
  WHERE
    a.admission_type = 'EMERGENCY'
), HospitalStay AS (
  SELECT
    ai.hadm_id,
    ai.subject_id,
    ai.dischtime,
    ai.admittime,
    TIMESTAMP_DIFF(ai.dischtime, ai.admittime, DAY) AS los
  FROM
    AdmissionInfo AS ai
)
SELECT
  MAX(los)
FROM
  HospitalStay;