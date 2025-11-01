WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.anchor_age BETWEEN 75 AND 85
    AND p.gender = 'M'
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
), SepsisDiagnosis AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  WHERE
    d.icd_code = 'A41.9' -- Sepsis without organism
    AND d.icd_version = 9
), Comorbidities AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  WHERE
    d.icd_code IN ('585.9', '585.1', '585.2', '585.3', '585.4', '585.5', '585.6', '585.8', '585.9', '401.9', '401.1', '401.3', '401.8', '401.9', '427.31', '427.39', '427.41', '427.49', '427.51', '427.59', '427.6', '427.89', '428.0', '428.1', '428.2', '428.3', '428.4', '428.5', '428.8', '428.9', '429.79', '429.89', '429.9', '431.0', '431.1', '431.31', '431.32', '431.33', '431.34', '431.39', '431.81', '431.82', '431.89', '431.9', '434.0', '434.1', '434.9', '435.1', '435.8', '435.9', '436.0', '436.1', '436.3', '436.5', '436.7', '436.8', '436.9', '437.0', '437.1', '437.2', '437.3', '437.9', '438.0', '438.1', '438.2', '438.3', '438.4', '438.5', '438.6', '438.7', '438.8', '438.9', '440.0', '440.1', '440.2', '440.3', '440.4', '440.5', '440.8', '440.9', '441.1', '441.8', '441.9', '442.0', '442.1', '442.2', '442.3', '442.4', '442.5', '442.6', '442.7', '442.8;