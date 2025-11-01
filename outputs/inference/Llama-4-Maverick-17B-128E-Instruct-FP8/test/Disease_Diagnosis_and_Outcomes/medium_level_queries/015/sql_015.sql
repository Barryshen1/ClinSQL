WITH 
-- Step 1: Identify stroke admissions
stroke_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 48 AND 58
  AND d_diag.long_title LIKE '%stroke%'  -- Simplified stroke identification
),

-- Step 2: Calculate in-hospital mortality, LOS, and ICU status
patient_outcomes AS (
  SELECT 
    sa.subject_id, sa.hadm_id,
    a.hospital_expire_flag AS in_hospital_mortality,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    icu.hadm_id IS NOT NULL AS icu_admission
  FROM stroke_admissions sa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON sa.hadm_id = a.hadm_id
  LEFT JOIN (SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`) icu ON sa.hadm_id = icu.hadm_id
),

-- Step 3: Calculate comorbidity burden (simplified as count of distinct diagnoses)
comorbidity_burden AS (
  SELECT hadm_id, COUNT(DISTINCT icd_code) AS num_comorbidities
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
)

-- Final analysis
SELECT 
  IF(po.icu_admission, 'ICU', 'Non-ICU') AS icu_status,
  IF(po.los <= 5, 'LOS <= 5', 'LOS > 5') AS los_category,
  -- Simplified comorbidity burden categorization
  IF(cb.num_comorbidities <= 3, 'Low', 'High') AS comorbidity_burden,
  COUNT(*) AS total_patients,
  SUM(po.in_hospital_mortality) AS num_deaths,
  -- Calculate mortality rate and 95% CI
  (SUM(po.in_hospital_mortality) / COUNT(*)) * 100 AS mortality_rate,
  -- Simplified 95% CI calculation using binomial proportion CI
  ((SUM(po.in_hospital_mortality) / COUNT(*)) + 1.96 * SQRT((SUM(po.in_hospital_mortality) / COUNT(*)) * (1 - (SUM(po.in_hospital_mortality) / COUNT(*))) / COUNT(*))) * 100 AS mortality_rate_upper_ci,
  ((SUM(po.in_hospital_mortality) / COUNT(*)) - 1.96 * SQRT((SUM(po.in_hospital_mortality) / COUNT(*)) * (1 - (SUM(po.in_hospital_mortality) / COUNT(*))) / COUNT(*))) * 100 AS mortality_rate_lower_ci
FROM patient_outcomes po
INNER JOIN comorbidity_burden cb ON po.hadm_id = cb.hadm_id
GROUP BY icu_status, los_category, comorbidity_burden
ORDER BY icu_status, los_category, comorbidity_burden;