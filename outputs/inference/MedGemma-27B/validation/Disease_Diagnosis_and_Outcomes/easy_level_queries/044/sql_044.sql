WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
), AdmissionInfo AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    admission_type,
    -- Calculate length of stay
    (TIMESTAMP_DIFF(dischtime, admitime, SECOND) / 3600) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
), DiagnosisInfo AS (
  SELECT
    hadm_id,
    icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    seq_num = 1 -- Primary diagnosis
    AND icd_version = 9 -- Assuming ICD-9 for heart failure codes
), ICDCodes AS (
  SELECT
    icd_code,
    long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    icd_version = 9
)
SELECT
  AVG(AdmissionInfo.los) AS average_los
FROM
  AdmissionInfo
INNER JOIN
  PatientInfo ON AdmissionInfo.subject_id = PatientInfo.subject_id
INNER JOIN
  DiagnosisInfo ON AdmissionInfo.hadm_id = DiagnosisInfo.hadm_id
INNER JOIN
  ICDCodes ON DiagnosisInfo.icd_code = ICDCodes.icd_code
WHERE
  PatientInfo.gender = 'F'
  AND PatientInfo.anchor_age BETWEEN 61 AND 71
  AND ICDCodes.long_title LIKE '%Heart Failure%';