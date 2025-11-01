WITH 
-- Identify DKA admissions
dka_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code IN ('250.1', '250.12', '250.13', 'E10.65', 'E11.65', 'E13.65')
),

-- Identify serum glucose lab events
glucose_events AS (
  SELECT 
    le.hadm_id,
    le.valuenum AS glucose_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli 
  ON le.itemid = dli.itemid
  WHERE dli.label = 'Glucose'
  AND le.valuenum IS NOT NULL
),

-- Find peak glucose for each admission
peak_glucose_admissions AS (
  SELECT 
    hadm_id,
    MAX(glucose_value) AS peak_glucose
  FROM glucose_events
  GROUP BY hadm_id
),

-- Filter for female DKA admissions
female_dka_admissions AS (
  SELECT 
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
  AND a.hadm_id IN (SELECT hadm_id FROM dka_admissions)
)

-- Find median peak glucose for female DKA admissions
SELECT 
  APPROX_QUANTILES(peak_glucose, 0.5) AS median_peak_glucose
FROM (
  SELECT peak_glucose
  FROM peak_glucose_admissions
  WHERE hadm_id IN (SELECT hadm_id FROM female_dka_admissions)
);