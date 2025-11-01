WITH PatientTIA AS (
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND d.icd_code = 'I63' -- TIA code
),
AdmissionTIA AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN PatientTIA AS pt
    ON a.subject_id = pt.subject_id
),
CTMRIProcedures AS (
  SELECT DISTINCT
    a.hadm_id,
    p.icd_code
  FROM AdmissionTIA AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
    ON a.hadm_id = p.hadm_id
  WHERE
    p.icd_code IN ('93.81', '93.82', '93.83', '93.84', '93.85', '93.86', '93.87', '93.88', '93.89', '93.90', '93.91', '93.92', '93.93', '93.94', '93.95', '93.96', '93.97', '93.98', '93.99', '94.00', '94.01', '94.02', '94.03', '94.04', '94.05', '94.06', '94.07', '94.08', '94.09', '94.10', '94.11', '94.12', '94.13', '94.14', '94.15', '94.16', '94.17', '94.18', '94.19', '94.20', '94.21', '94.22', '94.23', '94.24', '94.25', '94.26', '94.27', '94.28', '94.29', '94.30', '94.31', '94.32', '94.33', '94.34', '94.35', '94.36', '94.37', '94.38', '94.39', '94.40', '94.41', '94.42', '94.43', '94.44', '94.45', '94.46', ';