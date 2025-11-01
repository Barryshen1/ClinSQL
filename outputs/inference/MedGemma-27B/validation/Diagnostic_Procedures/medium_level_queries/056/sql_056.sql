WITH PatientDiagnosis AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hadm_id,
    d.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.icd_code = 'K85' -- ICD-9 code for acute pancreatitis
    AND d.seq_num = 1 -- Assuming the primary diagnosis is the first one listed
), PatientLOS AS (
  SELECT
    subject_id,
    hadm_id,
    -- Calculate length of stay in days
    CAST(TIMESTAMP_DIFF(dischtime, admittime, DAY) AS INT64) AS los
  FROM PatientDiagnosis
), PatientProcedures AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    pr.icd_code,
    pr.chartdate
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pr
    ON a.hadm_id = pr.hadm_id
  WHERE
    pr.icd_code IN ('93.50', '93.51', '93.52', '93.53', '93.54', '93.55', '93.56', '93.57', '93.58', '93.59', '93.60', '93.61', '93.62', '93.63', '93.64', '93.65', '93.66', '93.67', '93.68', '93.69', '93.70', '93.71', '93.72', '93.73', '93.74', '93.75', '93.76', '93.77', '93.78', '93.79', '93.80', '93.81', '93.82', '93.83', '93.84', '93.85', '93.86', '93.87', '93.88', '93.89', '93.90', '93.91', '93.92', '93.93', '93.94', '93.95', '93.96', '93.97', '93.98', '93.9;