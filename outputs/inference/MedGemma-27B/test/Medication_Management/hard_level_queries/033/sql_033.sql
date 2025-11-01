WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 80 AND 90
), SepsisDiagnosis AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id
  FROM PatientInfo AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id AND p.hadm_id = d.hadm_id
  WHERE
    d.icd_code IN ('A41.9', 'A41.4', 'A41.5', 'A41.2', 'A41.1', 'A41.3', 'A41.8', 'A41.0', 'A40.9', 'A40.3', 'A40.0', 'A40.1', 'A40.2', 'A40.8', 'A40.4', 'A40.5', 'A40.7', 'A40.6', 'A39.8', 'A39.5', 'A39.0', 'A39.1', 'A39.2', 'A39.3', 'A39.4', 'A39.6', 'A39.7', 'A39.9', 'A38.0', 'A38.1', 'A38.2', 'A38.3', 'A38.4', 'A38.5', 'A38.6', 'A38.7', 'A38.8', 'A38.9', 'A36.8', 'A36.9', 'A36.0', 'A36.1', 'A36.2', 'A36.3', 'A36.4', 'A36.5', 'A36.6', 'A36.7', 'A36.8', 'A36.9', 'A36.0', 'A36.1', 'A36.2', 'A36.3', 'A36.4', 'A36.5', 'A36.6', 'A36.7', 'A36.8', 'A36.9', 'A36.0', 'A36.1', 'A36.2', 'A36.3', 'A36.4', 'A36.5', 'A36.6', 'A36.7', 'A36.8', 'A36.9', 'A36.0', 'A36.1', 'A36.2', 'A36.3', 'A36.4', 'A36.5', 'A36.6', 'A36.7', 'A36.8', 'A36.9', 'A36.0', 'A36.1', 'A36.2', 'A36.3', 'A36.4', 'A36.5', 'A36.6', 'A36.7', 'A36.8', 'A36.9', 'A36.0', 'A36.1', 'A36.2', 'A36.3', 'A36.4', 'A36.5', 'A36.6', 'A36.7', 'A36.8', 'A36.9', 'A36.0', 'A36.1', 'A36.2', 'A36.3', 'A36.4', 'A36.5', 'A36.6', 'A36.7', 'A36.8', 'A36;