WITH
-- Get patient demographics (men 75-85)
patient_demo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year,
    dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 75 AND 85
),

-- Get first admission for each patient
first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    patient_demo p ON a.subject_id = p.subject_id
  WHERE
    a.admission_type != 'NEWBORN'  -- Exclude newborn admissions
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) = 1
),

-- Identify sepsis cases (excluding septic shock)
sepsis_cases AS (
  SELECT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    -- Sepsis codes (excluding septic shock)
    (d.icd_version = 9 AND d.icd_code IN ('995.91', '995.92') AND d.icd_code NOT IN ('785.52'))
    OR
    (d.icd_version = 10 AND d.icd_code IN ('R65.20', 'R65.21') AND d.icd_code NOT IN ('R65.21'))
),

-- Identify comorbidities
comorbidities AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    MAX(CASE WHEN di.icd_code IN ('585.1', '585.2', '585.3', '585.4', '585.5', '585.6', '585.9', 'N18.1', 'N18.2', 'N18.3', 'N18.4', 'N18.5', 'N18.6', 'N18.9') THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN di.icd_code IN ('250.00', '250.01', '250.02', '250.03', '250.10', '250.11', '250.12', '250.13', '250.20', '250.21', '250.22', '250.23', '250.30', '250.31', '250.32', '250.33', '250.40', '250.41', '250.42', '250.43', '250.50', '250.51', '250.52', '250.53', '250.60', '250.61', '250.62', '250.63', '250.70', '250.71', '250.72', '250.73', '250.80', '250.81', '250.82', '250.83', '250.90', '250.91', '250.92', '250.93', 'E11.65', 'E11.648', 'E11.649', 'E11.65', 'E11.69', 'E11.8', 'E11.9', 'E13.65', 'E13.648', 'E13.649', 'E13.65', 'E13.69', 'E13.8', 'E13.9') THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN di.icd_code IN ('427.31', 'I48.0', 'I48.1', 'I48.2', 'I48.3', 'I48.4', 'I48.91', 'I48.92') THEN 1 ELSE 0 END) AS has_afib,
    MAX(CASE WHEN di.icd_code IN ('401.0', '401.1', '401.9', '402.00', '402.01', '402.10', '402.11', '402.90', '402.91', '403.00', '403.01', '403.10', '403.11', '403.90', '403.91', '404.00', '404.01', '404.02', '404.03', '404.10', '404.11', '404.12', '404.13', '404.90', '404.91', '404.92', '404.93', 'I10', 'I11.0', 'I11.9', 'I12.0', 'I12.9', 'I13.0', 'I13.1', 'I13.10', 'I13.11', 'I13.2', 'I15.0', 'I15.1', 'I15.2', 'I15.8', 'I15.9') THEN 1 ELSE 0 END) AS has_hypertension
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  GROUP BY
    d.subject_id, d.hadm_id
),

-- Combine all data
combined_data AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.los_days,
    fa.hospital_expire_flag,
    c.has_ckd,
    c.has_diabetes,
    c.has_afib,
    c.has_hypertension
  FROM
    first_admissions fa
  JOIN
    sepsis_cases s ON fa.subject_id = s.subject_id AND fa.hadm_id = s.hadm_id
  LEFT JOIN
    comorbidities c ON fa.subject_id = c.subject_id AND fa.hadm_id = c.hadm_id
)

-- Final calculation
SELECT
  CASE WHEN los_days <= 5 THEN '≤5 days' ELSE '>5 days' END AS los_stratification,
  has_ckd,
  has_diabetes,
  has_afib,
  has_hypertension,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_percentage
FROM
  combined_data
GROUP BY
  los_stratification, has_ckd, has_diabetes, has_afib, has_hypertension
ORDER BY
  los_stratification, has_ckd, has_diabetes, has_afib, has_hypertension;