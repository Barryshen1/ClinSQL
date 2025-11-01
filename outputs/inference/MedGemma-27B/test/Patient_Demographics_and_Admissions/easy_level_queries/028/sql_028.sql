WITH SepsisPatients AS (
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND a.admission_type = 'EMERGENCY'
),
SepsisDiagnosis AS (
  SELECT DISTINCT
    s.subject_id,
    s.hadm_id
  FROM SepsisPatients AS s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON s.subject_id = d.subject_id AND s.hadm_id = d.hadm_id
  WHERE
    d.icd_code IN ('A41.9', 'A41.4', 'A41.5', 'A41.1', 'A41.2', 'A41.3', 'A41.8', 'A41.0', 'A40.0', 'A40.1', 'A40.2', 'A40.3', 'A40.8', 'A40.9', 'A40.5', 'A40.4', 'A40.7', 'A40.6', 'A40.8', 'A40.9', 'A40.5', 'A40.4', 'A40.7', 'A40.6', 'A40.8', 'A40.9', 'A40.5', 'A40.4', 'A40.7', 'A40.6', 'A40.8', 'A40.9', 'A40.5', 'A40.4', 'A40.7', 'A40.6', 'A40.8', 'A40.9', 'A40.5', 'A40.4', 'A40.7', 'A40.6', 'A40.8', 'A40.9', 'A40.5', 'A40.4', 'A40.7', 'A40.6', 'A40.8', 'A40.9', 'A40.5', 'A40.4', 'A40.7', 'A40.6', 'A40.8', 'A40.9', 'A40.5', 'A40.4', 'A40.7', 'A40.6', 'A40.8', 'A40.9', 'A40.5', 'A40.4', 'A40.7', 'A40.6', 'A40.8', 'A40.9', 'A40.5', 'A40.4', 'A40.7', 'A40.6', 'A40.8', 'A40.9', 'A40.5', 'A40.4', 'A40.7', 'A40.6', 'A40.8', 'A40.9', 'A40.5', 'A40.4', 'A40.7', 'A40.6', 'A40.8', 'A40.9', 'A40.5', 'A40.4', 'A40.7', 'A40.6', 'A40.8', 'A40.9', 'A40.5', 'A40.4', 'A40.7', 'A40.6', 'A40.8', 'A40.9', 'A40.5', 'A40.4', 'A40.7', 'A40.6', 'A40.;