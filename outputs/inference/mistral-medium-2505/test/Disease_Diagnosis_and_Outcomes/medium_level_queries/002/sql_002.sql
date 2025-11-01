WITH
-- Define age at admission
patient_age AS (
  SELECT
    p.subject_id,
    gender,
    anchor_age,
    anchor_year,
    EXTRACT(YEAR FROM admittime) AS admission_year,
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
),

-- Identify AMI patients
ami_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.icd_code LIKE 'I21.%'  -- AMI ICD-10 codes
),

-- Exclude patients with shock or respiratory failure
excluded_patients AS (
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    (di.icd_code LIKE 'R57.%' OR  -- Shock
     di.icd_code LIKE 'J96.%')  -- Respiratory failure
),

-- Identify CKD and diabetes
comorbidities AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(CASE WHEN di.icd_code LIKE 'N18.%' OR di.icd_code LIKE 'I12.%' OR di.icd_code LIKE 'I13.%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN di.icd_code LIKE 'E11.%' OR di.icd_code LIKE 'E13.%' OR di.icd_code LIKE 'E14.%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  GROUP BY
    subject_id, hadm_id
),

-- Combine all data
combined_data AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    pa.age_at_admission,
    pa.gender,
    a.hospital_expire_flag,
    a.los_days,
    c.has_ckd,
    c.has_diabetes
  FROM
    ami_patients a
  JOIN
    patient_age pa
  ON
    a.subject_id = pa.subject_id
  JOIN
    comorbidities c
  ON
    a.subject_id = c.subject_id AND a.hadm_id = c.hadm_id
  WHERE
    pa.gender = 'F'
    AND pa.age_at_admission BETWEEN 62 AND 72
    AND NOT EXISTS (
      SELECT 1
      FROM excluded_patients e
      WHERE e.subject_id = a.subject_id AND e.hadm_id = a.hadm_id
    )
)

-- Final analysis
SELECT
  CASE WHEN los_days <= 5 THEN 'LOS ≤5 days' ELSE 'LOS >5 days' END AS los_group,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate,
  ROUND(SUM(has_ckd) * 100.0 / COUNT(*), 2) AS ckd_prevalence,
  ROUND(SUM(has_diabetes) * 100.0 / COUNT(*), 2) AS diabetes_prevalence,
  -- Absolute mortality difference (LOS >5 - LOS ≤5)
  ROUND(
    (SUM(CASE WHEN los_days > 5 THEN hospital_expire_flag ELSE 0 END) * 100.0 / SUM(CASE WHEN los_days > 5 THEN 1 ELSE 0 END)) -
    (SUM(CASE WHEN los_days <= 5 THEN hospital_expire_flag ELSE 0 END) * 100.0 / SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END)),
    2
  ) AS absolute_mortality_difference,
  -- Relative mortality difference (LOS >5 / LOS ≤5)
  ROUND(
    (SUM(CASE WHEN los_days > 5 THEN hospital_expire_flag ELSE 0 END) * 100.0 / SUM(CASE WHEN los_days > 5 THEN 1 ELSE 0 END)) /
    NULLIF((SUM(CASE WHEN los_days <= 5 THEN hospital_expire_flag ELSE 0 END) * 100.0 / SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END)), 0),
    2
  ) AS relative_mortality_difference
FROM
  combined_data
GROUP BY
  los_group
ORDER BY
  los_group;