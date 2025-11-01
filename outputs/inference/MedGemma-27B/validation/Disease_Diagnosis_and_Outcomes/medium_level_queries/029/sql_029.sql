WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
), AdmissionInfo AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
), DiagnosisInfo AS (
  SELECT
    hadm_id,
    seq_num,
    icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
), ICDCodes AS (
  SELECT
    icd_code,
    long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
), SepsisInfo AS (
  SELECT
    hadm_id,
    CASE
      WHEN icd_code IN ('A41.9', 'A41.1', 'A41.2', 'A41.3', 'A41.4', 'A41.5', 'A41.8', 'A41.0', 'A40.0', 'A40.1', 'A40.2', 'A40.3', 'A40.8', 'A40.9', 'A41.9', 'A41.1', 'A41.2', 'A41.3', 'A41.4', 'A41.5', 'A41.8', 'A41.0', 'A40.0', 'A40.1', 'A40.2', 'A40.3', 'A40.8', 'A40.9', 'A41.9', 'A41.1', 'A41.2', 'A41.3', 'A41.4', 'A41.5', 'A41.8', 'A41.0', 'A40.0', 'A40.1', 'A40.2', 'A40.3', 'A40.8', 'A40.9', 'A41.9', 'A41.1', 'A41.2', 'A41.3', 'A41.4', 'A41.5', 'A41.8', 'A41.0', 'A40.0', 'A40.1', 'A40.2', 'A40.3', 'A40.8', 'A40.9', 'A41.9', 'A41.1', 'A41.2', 'A41.3', 'A41.4', 'A41.5', 'A41.8', 'A41.0', 'A40.0', 'A40.1', 'A40.2', 'A40.3', 'A40.8', 'A40.9', 'A41.9', 'A41.1', 'A41.2', 'A41.3', 'A41.4', 'A41.5', 'A41.8', 'A41.0', 'A40.0', 'A40.1', 'A40.2', 'A40.3', 'A40.8', 'A40.9', 'A41.9', 'A41.1', 'A41.2', 'A41.3', 'A41.4', 'A41.5', 'A41.8', 'A41.0', 'A40.0', 'A40.1', 'A40.2', 'A40.3', 'A40.8', 'A40.9', 'A41.9', 'A41.1', 'A41.2', 'A41.3', 'A41.4', 'A41.5', 'A41.8', 'A41.0', 'A40.0', 'A40.1;