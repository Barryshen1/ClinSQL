WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age = 45
    AND gender = 'F'
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    d.long_title AS diagnosis_title,
    d.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag ON a.hadm_id = diag.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d ON diag.icd_code = d.icd_code
    AND diag.icd_version = d.icd_version
  WHERE
    diag.seq_num = 1
    AND (
      d.long_title LIKE '%ischemic heart disease%'
      OR d.long_title LIKE '%acute coronary syndrome%'
      OR d.long_title LIKE '%myocardial infarction%'
    )
), ICUStayInfo AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  INNER JOIN
    AdmissionInfo AS ai ON ic.subject_id = ai.subject_id
    AND ic.hadm_id = ai.hadm_id
)
SELECT
  PERCENTILE_CONT(0.25, los) AS percentile_25_los
FROM
  ICUStayInfo;