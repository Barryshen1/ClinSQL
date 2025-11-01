WITH
-- Get heart failure patients (male, age 38-48)
hf_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Check if patient had any ICU stay
    MAX(CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS had_icu_stay
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
    AND p.subject_id IN (
      -- Patients with heart failure diagnosis
      SELECT DISTINCT d.subject_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.icd_code IN (
        'I500', 'I501', 'I509', 'I110', 'I130', 'I132' -- Heart failure ICD-10 codes
      )
    )
  GROUP BY
    p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
),

-- Calculate Charlson Comorbidity Index (simplified version)
charlson_scores AS (
  SELECT
    subject_id,
    hadm_id,
    -- Count of comorbidities (simplified - in real analysis would use proper Charlson weights)
    COUNT(DISTINCT icd_code) AS comorbidity_count,
    -- Categorize Charlson score (simplified)
    CASE
      WHEN COUNT(DISTINCT icd_code) <= 3 THEN '≤3'
      WHEN COUNT(DISTINCT icd_code) BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    subject_id, hadm_id
),

-- Combine all data
patient_data AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.hospital_expire_flag,
    h.los_days,
    h.had_icu_stay,
    c.comorbidity_count,
    c.charlson_category,
    -- Categorize LOS
    CASE
      WHEN h.los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN h.los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE '≥8'
    END AS los_category
  FROM
    hf_patients h
  JOIN
    charlson_scores c ON h.subject_id = c.subject_id AND h.hadm_id = c.hadm_id
  WHERE
    h.los_days > 0 -- Exclude same-day discharges
)

-- Final aggregation with mortality and comorbidity statistics
SELECT
  CASE WHEN had_icu_stay = 1 THEN 'ICU' ELSE 'No ICU' END AS icu_status,
  los_category,
  charlson_category,
  -- Mortality statistics
  COUNT(*) AS patient_count,
  SUM(hospital_expire_flag) AS death_count,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 1) AS mortality_percentage,
  -- Wilson score interval for 95% CI
  ROUND(100 * (
    (SUM(hospital_expire_flag) + 1.96*1.96/2) /
    (COUNT(*) + 1.96*1.96) -
    1.96*1.96/(2*(COUNT(*) + 1.96*1.96)) +
    1.96*SQRT(
      (SUM(hospital_expire_flag)*(COUNT(*) - SUM(hospital_expire_flag)))/COUNT(*) +
      1.96*1.96/4
    ) / (COUNT(*) + 1.96*1.96)
  ), 1) AS mortality_ci_upper,
  ROUND(100 * (
    (SUM(hospital_expire_flag) + 1.96*1.96/2) /
    (COUNT(*) + 1.96*1.96) -
    1.96*1.96/(2*(COUNT(*) + 1.96*1.96)) -
    1.96*SQRT(
      (SUM(hospital_expire_flag)*(COUNT(*) - SUM(hospital_expire_flag)))/COUNT(*) +
      1.96*1.96/4
    ) / (COUNT(*) + 1.96*1.96)
  ), 1) AS mortality_ci_lower,
  -- Comorbidity statistics
  ROUND(AVG(comorbidity_count), 1) AS mean_comorbidity_count
FROM
  patient_data
GROUP BY
  icu_status, los_category, charlson_category
ORDER BY
  icu_status, los_category, charlson_category;