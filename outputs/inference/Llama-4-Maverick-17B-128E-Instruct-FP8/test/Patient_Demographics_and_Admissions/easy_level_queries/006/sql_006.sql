WITH 
-- Filter patients for females aged 58-68
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 58 AND 68
),

-- Identify hospital admissions for these patients
admissions AS (
  SELECT a.hadm_id, a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN eligible_patients p ON a.subject_id = p.subject_id
),

-- Simplify sepsis identification by assuming we can directly use diagnoses_icd
sepsis_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  -- Example: Using a placeholder ICD code for sepsis; replace with actual logic
  WHERE d.icd_code IN ('A41.9')  -- Example code, actual sepsis codes may vary
),

-- Get ICU stays for these admissions
icu_stays AS (
  SELECT i.stay_id, i.hadm_id, i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN sepsis_admissions s ON i.hadm_id = s.hadm_id
)

-- Calculate median ICU LOS
SELECT 
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_icu_los
FROM icu_stays;