WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    insurance
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.admission_type,
    a.admission_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.insurance
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    PatientInfo AS p ON a.subject_id = p.subject_id
), DiagnosisInfo AS (
  SELECT
    a.hadm_id,
    d.icd_code,
    d.seq_num
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d ON a.hadm_id = d.hadm_id
)
SELECT
  COUNT(DISTINCT ai.hadm_id)
FROM
  AdmissionInfo AS ai
INNER JOIN
  DiagnosisInfo AS di ON ai.hadm_id = di.hadm_id
WHERE
  ai.gender = 'M'
  AND ai.insurance = 'Medicare'
  AND ai.anchor_age BETWEEN 43 AND 53
  AND ai.admission_location = 'EMERGENCY'
  AND di.seq_num = 1
  AND di.icd_code = 'E11.10';