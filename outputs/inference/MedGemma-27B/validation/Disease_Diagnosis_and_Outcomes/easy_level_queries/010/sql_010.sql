WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 49 AND 59
), AdmissionInfo AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    PatientInfo AS p
    ON a.subject_id = p.subject_id
  WHERE
    a.admission_type = 'EMERGENCY'
), DiagnosisInfo AS (
  SELECT
    a.hadm_id,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  INNER JOIN
    AdmissionInfo AS a
    ON d.hadm_id = a.hadm_id
  WHERE
    d.seq_num = 1
), COPDDiagnosis AS (
  SELECT
    a.hadm_id
  FROM
    DiagnosisInfo AS d
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code
  INNER JOIN
    AdmissionInfo AS a
    ON d.hadm_id = a.hadm_id
  WHERE
    di.long_title LIKE '%COPD%' OR di.long_title LIKE '%Chronic Obstructive Pulmonary Disease%'
), FinalAdmissionInfo AS (
  SELECT
    a.hadm_id,
    a.dischtime,
    a.deathtime
  FROM
    AdmissionInfo AS a
  INNER JOIN
    COPDDiagnosis AS c
    ON a.hadm_id = c.hadm_id
)
SELECT
  PERCENTILE_CONT(0.25, TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS percentile_25_los
FROM
  FinalAdmissionInfo
WHERE
  dischtime IS NOT NULL;