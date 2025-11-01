WITH sepsis_patients AS (
  -- Identify male patients aged 52-62 with sepsis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.hospital_expire_flag,
    -- Calculate LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Identify septic shock (using ICD code R65.21)
    MAX(CASE WHEN d.icd_code = 'R6521' THEN 1 ELSE 0 END) AS has_septic_shock,
    -- Count comorbidities (excluding sepsis codes)
    COUNT(DISTINCT CASE WHEN d.icd_code NOT LIKE 'A4%' AND d.icd_code NOT LIKE 'R65%' THEN d.icd_code END) AS comorbidity_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    -- Include common sepsis codes
    AND (d.icd_code LIKE 'A4%' OR d.icd_code LIKE 'R65%')
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.admission_type, a.hospital_expire_flag
),

los_categories AS (
  -- Categorize LOS into groups
  SELECT
    *,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
      WHEN los_days >= 8 THEN '8+ days'
      ELSE 'Other'
    END AS los_category
  FROM
    sepsis_patients
)

-- Final aggregation
SELECT
  CASE WHEN has_septic_shock = 1 THEN 'Septic Shock' ELSE 'No Shock' END AS sepsis_severity,
  los_category,
  admission_type,
  COUNT(*) AS patient_count,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 1) AS in_hospital_mortality_pct,
  ROUND(AVG(comorbidity_count), 1) AS mean_comorbidity_count
FROM
  los_categories
GROUP BY
  sepsis_severity, los_category, admission_type
ORDER BY
  sepsis_severity, los_category, admission_type;