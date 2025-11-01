WITH
-- Filter for 51-61 year old males
patient_filter AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 51 AND 61
),

-- Get admissions with postoperative complications
postop_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Calculate Charlson Comorbidity Index (simplified example)
    SUM(CASE
      WHEN d.icd_code IN ('585', '586', '585.1', '585.2', '585.3', '585.4', '585.5', '585.6', '585.9') THEN 1 -- CKD
      WHEN d.icd_code IN ('250', '250.0', '250.1', '250.2', '250.3', '250.4', '250.5', '250.6', '250.7', '250.8', '250.9') THEN 1 -- Diabetes
      ELSE 0
    END) AS cci_score,
    MAX(CASE WHEN d.icd_code IN ('585', '586', '585.1', '585.2', '585.3', '585.4', '585.5', '585.6', '585.9') THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN d.icd_code IN ('250', '250.0', '250.1', '250.2', '250.3', '250.4', '250.5', '250.6', '250.7', '250.8', '250.9') THEN 1 ELSE 0 END) AS has_diabetes
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    patient_filter p ON a.subject_id = p.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.subject_id = diag.subject_id AND a.hadm_id = diag.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE
    a.admission_type = 'ELECTIVE' -- Assuming postoperative complications are elective admissions
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, i.stay_id
),

-- Stratify by LOS and CCI
stratified_data AS (
  SELECT
    icu_status,
    CASE
      WHEN los_days BETWEEN 1 AND 2 THEN '1-2 days'
      WHEN los_days BETWEEN 3 AND 5 THEN '3-5 days'
      WHEN los_days BETWEEN 6 AND 9 THEN '6-9 days'
      WHEN los_days >= 10 THEN '≥10 days'
      ELSE 'Other'
    END AS los_stratum,
    CASE
      WHEN cci_score BETWEEN 0 AND 1 THEN '0-1'
      WHEN cci_score = 2 THEN '2'
      WHEN cci_score >= 3 THEN '≥3'
      ELSE 'Unknown'
    END AS cci_stratum,
    COUNT(*) AS patient_count,
    SUM(hospital_expire_flag) AS deaths,
    SUM(has_ckd) AS ckd_count,
    SUM(has_diabetes) AS diabetes_count,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los
  FROM
    postop_admissions
  GROUP BY
    icu_status, los_stratum, cci_stratum
)

-- Final output
SELECT
  icu_status,
  los_stratum,
  cci_stratum,
  patient_count,
  ROUND(100 * deaths / patient_count, 1) AS mortality_percentage,
  median_los,
  ROUND(100 * ckd_count / patient_count, 1) AS ckd_prevalence_percentage,
  ROUND(100 * diabetes_count / patient_count, 1) AS diabetes_prevalence_percentage
FROM
  stratified_data
ORDER BY
  icu_status, los_stratum, cci_stratum;