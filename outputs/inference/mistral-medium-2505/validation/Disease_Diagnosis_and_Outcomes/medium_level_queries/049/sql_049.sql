WITH
-- Get male patients aged 51-61
patient_base AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 51 AND 61
),

-- Get first admission for each patient
first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS admission_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    patient_base p ON a.subject_id = p.subject_id
  WHERE
    a.hospital_expire_flag IS NOT NULL
),

-- Get STEMI/NSTEMI diagnoses
mi_diagnoses AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    d.icd_version,
    di.long_title,
    CASE
      WHEN d.icd_code LIKE 'I21.0%' OR d.icd_code LIKE 'I21.1%' OR d.icd_code LIKE 'I21.2%' OR d.icd_code LIKE 'I21.3%' OR d.icd_code = 'I21.9' THEN 'STEMI'
      WHEN d.icd_code = 'I21.4' THEN 'NSTEMI'
      ELSE NULL
    END AS mi_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    (d.icd_code LIKE 'I21.0%' OR d.icd_code LIKE 'I21.1%' OR d.icd_code LIKE 'I21.2%' OR d.icd_code LIKE 'I21.3%' OR d.icd_code = 'I21.4' OR d.icd_code = 'I21.9')
    AND d.icd_version = 10
),

-- Get all other diagnoses (comorbidities)
comorbidities AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    di.long_title,
    CASE
      WHEN d.icd_code LIKE 'N18%' THEN 'CKD'
      WHEN d.icd_code LIKE 'E11%' THEN 'Diabetes'
      ELSE 'Other'
    END AS comorbidity_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    d.icd_version = 10
    AND d.icd_code NOT LIKE 'I21%'
),

-- Count comorbidities per admission
comorbidity_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS total_comorbidities,
    MAX(CASE WHEN comorbidity_type = 'CKD' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN comorbidity_type = 'Diabetes' THEN 1 ELSE 0 END) AS has_diabetes
  FROM
    comorbidities
  GROUP BY
    hadm_id
),

-- Combine all data
combined_data AS (
  SELECT
    fa.hadm_id,
    fa.los_days,
    md.mi_type,
    cc.total_comorbidities,
    cc.has_ckd,
    cc.has_diabetes,
    fa.hospital_expire_flag
  FROM
    first_admissions fa
  JOIN
    mi_diagnoses md ON fa.hadm_id = md.hadm_id
  JOIN
    comorbidity_counts cc ON fa.hadm_id = cc.hadm_id
  WHERE
    fa.admission_rank = 1
)

-- Final aggregation
SELECT
  mi_type,
  CASE
    WHEN los_days BETWEEN 1 AND 2 THEN '1-2 days'
    WHEN los_days BETWEEN 3 AND 5 THEN '3-5 days'
    WHEN los_days BETWEEN 6 AND 9 THEN '6-9 days'
    WHEN los_days >= 10 THEN '≥10 days'
    ELSE 'Unknown'
  END AS los_group,
  CASE
    WHEN total_comorbidities BETWEEN 0 AND 1 THEN '0-1'
    WHEN total_comorbidities = 2 THEN '2'
    WHEN total_comorbidities >= 3 THEN '≥3'
    ELSE 'Unknown'
  END AS comorbidity_group,
  COUNT(*) AS n_patients,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 1) AS mortality_rate,
  ROUND(100 * SUM(has_ckd) / COUNT(*), 1) AS ckd_prevalence,
  ROUND(100 * SUM(has_diabetes) / COUNT(*), 1) AS diabetes_prevalence
FROM
  combined_data
GROUP BY
  mi_type, los_group, comorbidity_group
ORDER BY
  mi_type, los_group, comorbidity_group;