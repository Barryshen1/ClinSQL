WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 68 AND 78
),
AdmissionInfo AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.hospital_expire_flag,
    a.dischtime,
    a.admittime,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    PatientInfo AS p ON a.subject_id = p.subject_id
),
LOSCalculation AS (
  SELECT
    hadm_id,
    subject_id,
    hospital_expire_flag,
    -- Calculate length of stay in days
    -- Use TIMESTAMP_DIFF to calculate the difference between discharge time and admission time in days
    -- If dischtime is NULL, use the current time as the discharge time
    TIMESTAMP_DIFF(COALESCE(dischtime, CURRENT_TIMESTAMP()), admittime, DAY) AS los
  FROM
    AdmissionInfo
),
DiagnosisInfo AS (
  SELECT
    hadm_id,
    subject_id,
    -- Check for CKD diagnosis (ICD-10 codes)
    -- Use ARRAY_CONTAINS to check if any of the ICD codes are in the list of CKD codes
    ARRAY_CONTAINS(ARRAY['N18.1', 'N18.2', 'N18.3', 'N18.4', 'N18.5', 'N18.6', 'N18.9'], icd_code) AS has_ckd,
    -- Check for Diabetes diagnosis (ICD-10 codes)
    -- Use ARRAY_CONTAINS to check if any of the ICD codes are in the list of Diabetes codes
    ARRAY_CONTAINS(ARRAY['E10.10', 'E10.11', 'E10.12', 'E10.20', 'E10.21', 'E10.22', 'E10.30', 'E10.31', 'E10.32', 'E10.40', 'E10.41', 'E10.42', 'E10.50', 'E10.51', 'E10.52', 'E10.60', 'E10.61', 'E10.62', 'E10.70', 'E10.71', 'E10.72', 'E10.80', 'E10.81', 'E10.82', 'E10.90', 'E10.91', 'E10.92', 'E11.10', 'E11.11', 'E11.12', 'E11.20', 'E11.21', 'E11.22', 'E11.30', 'E11.31', 'E11.32', 'E11.40', 'E11.41', 'E11.42', 'E11.50', 'E11.51', 'E11.52', 'E11.60', 'E11.61', 'E11.62', 'E11.63', 'E11.64', 'E11.65', 'E11.66', 'E11.67', 'E11.68', 'E11.69', 'E11.70', 'E11.71', 'E11.72', 'E11.73', 'E11.74', 'E11.75', 'E11.76', 'E11.77', 'E11.78', 'E11.79', 'E11.80', 'E11.81', 'E11.82', 'E11.83', 'E11.84', 'E11.85', 'E;