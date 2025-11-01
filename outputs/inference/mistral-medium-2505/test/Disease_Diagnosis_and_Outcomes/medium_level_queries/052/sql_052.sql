WITH
-- Define age range and gender filter
patient_filter AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 52 AND 62
),

-- Get stroke patients
stroke_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patient_filter p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE d.icd_code IN ('I63', 'I64')  -- Stroke ICD codes
),

-- Calculate length of stay
los_calc AS (
  SELECT
    subject_id,
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS length_of_stay
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE hadm_id IN (SELECT hadm_id FROM stroke_patients)
),

-- Identify ICU stays
icu_stays AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE hadm_id IN (SELECT hadm_id FROM stroke_patients)
),

-- Calculate Charlson Comorbidity Index (simplified version)
cci_calc AS (
  SELECT
    d.hadm_id,
    SUM(CASE
      WHEN d.icd_code IN ('I63', 'I64') THEN 1  -- Stroke
      WHEN d.icd_code IN ('N18', 'E1122') THEN 2  -- CKD
      WHEN d.icd_code LIKE 'E11%' THEN 1  -- Diabetes
      WHEN d.icd_code LIKE 'E13%' THEN 1  -- Diabetes
      WHEN d.icd_code LIKE 'I25%' THEN 1  -- CAD
      WHEN d.icd_code LIKE 'I50%' THEN 1  -- CHF
      WHEN d.icd_code LIKE 'J44%' THEN 1  -- COPD
      WHEN d.icd_code LIKE 'C%' THEN 2  -- Cancer
      ELSE 0
    END) AS cci_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN stroke_patients s ON d.hadm_id = s.hadm_id
  GROUP BY d.hadm_id
),

-- Calculate tertiles for CCI
cci_tertiles AS (
  SELECT
    hadm_id,
    cci_score,
    NTILE(3) OVER (ORDER BY cci_score) AS cci_tertile
  FROM cci_calc
),

-- Combine all data
combined_data AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    CASE WHEN i.hadm_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
    CASE WHEN l.length_of_stay <= 5 THEN '≤5 days' ELSE '>5 days' END AS los_category,
    c.cci_tertile,
    a.hospital_expire_flag,
    MAX(CASE WHEN d.icd_code IN ('N18', 'E1122') THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN stroke_patients s ON a.hadm_id = s.hadm_id
  JOIN los_calc l ON a.hadm_id = l.hadm_id
  LEFT JOIN icu_stays i ON a.hadm_id = i.hadm_id
  JOIN cci_tertiles c ON a.hadm_id = c.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  GROUP BY
    a.hadm_id, a.subject_id, icu_status, los_category, cci_tertile, a.hospital_expire_flag
)

-- Final aggregation
SELECT
  icu_status,
  los_category,
  cci_tertile,
  COUNT(*) AS patient_count,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 1) AS mortality_percentage,
  ROUND(100 * SUM(has_ckd) / COUNT(*), 1) AS ckd_prevalence_percentage,
  ROUND(100 * SUM(has_diabetes) / COUNT(*), 1) AS diabetes_prevalence_percentage
FROM combined_data
GROUP BY icu_status, los_category, cci_tertile
ORDER BY icu_status, los_category, cci_tertile;