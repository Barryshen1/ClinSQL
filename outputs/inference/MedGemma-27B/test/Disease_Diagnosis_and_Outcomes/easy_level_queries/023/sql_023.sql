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
    -- Calculate length of stay (LOS) in days
    (TIMESTAMP_DIFF(dischtime, admittime, DAY) + 1) AS los
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
    AND icd_version = 9 -- Assuming ICD-9 for community-acquired pneumonia
), PneumoniaDiagnosis AS (
  SELECT
    icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    icd_code LIKE '486%' -- ICD-9 codes for pneumonia
    AND icd_version = 9
)
SELECT
  PERCENTILE_CONT(AdmissionInfo.los, 0.5) AS median_los
FROM
  AdmissionInfo
INNER JOIN
  PatientInfo ON AdmissionInfo.subject_id = PatientInfo.subject_id
INNER JOIN
  DiagnosisInfo ON AdmissionInfo.hadm_id = DiagnosisInfo.hadm_id
INNER JOIN
  PneumoniaDiagnosis ON DiagnosisInfo.icd_code = PneumoniaDiagnosis.icd_code
WHERE
  PatientInfo.gender = 'F'
  AND PatientInfo.anchor_age BETWEEN 83 AND 93
  AND AdmissionInfo.admission_type = 'EMERGENCY'; -- Assuming community-acquired pneumonia implies emergency admission;