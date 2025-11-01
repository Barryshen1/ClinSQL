WITH 
-- Define the cohort: female patients aged 68-78 admitted with HHS
hhs_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 68 AND 78
  AND dicd.long_title LIKE '%Hyperosmolar hyperglycemic state%'  -- Simplified HHS identification
),

-- Medications within the first 72 hours
early_medications AS (
  SELECT h.hadm_id, COUNT(DISTINCT pr.drug) AS num_drugs
  FROM hhs_patients h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON h.hadm_id = pr.hadm_id
  WHERE pr.starttime <= (h.admittime + INTERVAL 3 DAY)
  GROUP BY h.hadm_id
),

-- Hyperkalemia-risk drug interactions (simplified example)
hyperkalemia_risk AS (
  SELECT h.hadm_id, COUNT(DISTINCT pr.drug) AS num_hyperkalemia_risk_drugs
  FROM hhs_patients h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON h.hadm_id = pr.hadm_id
  WHERE pr.drug LIKE '%Potassium%' OR pr.drug LIKE '%Spironolactone%'  -- Example drugs that could increase K+
  GROUP BY h.hadm_id
),

-- Length of Stay (LOS) in ICU
icu_los AS (
  SELECT h.hadm_id, icu.los
  FROM hhs_patients h
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON h.hadm_id = icu.hadm_id
),

-- Mortality
mortality AS (
  SELECT h.hadm_id, a.deathtime IS NOT NULL AS died_in_hospital
  FROM hhs_patients h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON h.hadm_id = a.hadm_id
)

-- Main query to analyze the defined metrics
SELECT 
  PERCENTILE_CONT(num_drugs, 0.5) OVER () AS median_medication_complexity,
  PERCENTILE_CONT(num_hyperkalemia_risk_drugs, 0.5) OVER () AS median_hyperkalemia_risk,
  COUNT(CASE WHEN num_hyperkalemia_risk_drugs > 0 THEN 1 END) * 1.0 / COUNT(*) AS percent_affected,
  PERCENTILE_CONT(los, 0.75) OVER () AS top_quartile_los,  -- Corrected reference here
  COUNT(CASE WHEN died_in_hospital THEN 1 END) * 1.0 / COUNT(*) AS mortality_rate
FROM early_medications
JOIN hyperkalemia_risk ON early_medications.hadm_id = hyperkalemia_risk.hadm_id
JOIN icu_los ON early_medications.hadm_id = icu_los.hadm_id
JOIN mortality ON early_medications.hadm_id = mortality.hadm_id;