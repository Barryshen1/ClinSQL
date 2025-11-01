WITH
-- Get female patients aged 49-59
female_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 49 AND 59
),

-- Get admissions for these patients
patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 5 THEN '≤5 days' ELSE '>5 days' END AS los_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    female_patients p ON a.subject_id = p.subject_id
  WHERE
    -- Only include completed admissions
    a.dischtime IS NOT NULL
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
    -- Sepsis ICD codes (ICD-9 and ICD-10)
    (d.icd_code LIKE '995.91' OR d.icd_code LIKE '995.92' OR
     d.icd_code LIKE 'R65.2%' OR d.icd_code LIKE 'A41.9' OR
     d.icd_code LIKE 'A41.%' OR d.icd_code LIKE 'A40.%')
    -- Exclude septic shock
    AND d.icd_code NOT LIKE '785.52'  -- ICD-9 septic shock
    AND d.icd_code NOT LIKE 'R65.21'   -- ICD-10 septic shock
),

-- Identify day-1 ICU admissions
day1_icu AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    CASE WHEN DATE(i.intime) = DATE(a.admittime) THEN 'Day-1 ICU' ELSE 'Non-ICU' END AS icu_status
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    patient_admissions a ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
),

-- Identify CKD and Diabetes
ckd_diabetes AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    MAX(CASE WHEN d.icd_code LIKE 'N18.%' OR d.icd_code LIKE '585.%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN d.icd_code LIKE 'E11.%' OR d.icd_code LIKE 'E10.%' OR
                   d.icd_code LIKE 'E13.%' OR d.icd_code LIKE 'E14.%' OR
                   d.icd_code LIKE '250.%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY
    d.subject_id, d.hadm_id
),

-- Combine all information
combined_data AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.los_category,
    COALESCE(d1.icu_status, 'Non-ICU') AS icu_status,
    pa.hospital_expire_flag,
    ckd.has_ckd,
    ckd.has_diabetes
  FROM
    patient_admissions pa
  JOIN
    sepsis_cases s ON pa.subject_id = s.subject_id AND pa.hadm_id = s.hadm_id
  LEFT JOIN
    day1_icu d1 ON pa.subject_id = d1.subject_id AND pa.hadm_id = d1.hadm_id
  LEFT JOIN
    ckd_diabetes ckd ON pa.subject_id = ckd.subject_id AND pa.hadm_id = ckd.hadm_id
)

-- Final aggregation
SELECT
  los_category,
  icu_status,
  COUNT(DISTINCT subject_id) AS n,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(DISTINCT subject_id), 1) AS mortality_pct,
  ROUND(100 * SUM(has_ckd) / COUNT(DISTINCT subject_id), 1) AS ckd_prevalence_pct,
  ROUND(100 * SUM(has_diabetes) / COUNT(DISTINCT subject_id), 1) AS diabetes_prevalence_pct
FROM
  combined_data
GROUP BY
  los_category, icu_status
ORDER BY
  los_category, icu_status;