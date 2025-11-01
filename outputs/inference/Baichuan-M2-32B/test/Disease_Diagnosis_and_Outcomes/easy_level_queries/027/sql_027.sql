SELECT MAX(los_days) AS max_los_days
FROM (
  SELECT 
    TIMESTAMP_DIFF(COALESCE(admissions.dischtime, admissions.deathtime), admissions.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` admissions
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON admissions.subject_id = patients.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diagnoses
    ON admissions.subject_id = diagnoses.subject_id
    AND admissions.hadm_id = diagnoses.hadm_id
    AND diagnoses.seq_num = 1
    AND diagnoses.icd_code = 'K92.2'
    AND diagnoses.icd_version = 9
  WHERE patients.gender = 'F'
    AND patients.anchor_age BETWEEN 49 AND 59
    AND admissions.admittime IS NOT NULL
    AND (admissions.dischtime IS NOT NULL OR admissions.deathtime IS NOT NULL)
);