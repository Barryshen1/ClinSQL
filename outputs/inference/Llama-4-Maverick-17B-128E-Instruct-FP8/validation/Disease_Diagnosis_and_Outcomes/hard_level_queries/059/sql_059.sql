WITH 
-- Step 1: Identify the cohort (male inpatients aged 59-69 with DKA)
dka_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 59 AND 69
  AND dicd.long_title LIKE '%Diabetic ketoacidosis%'
),

-- Step 2: Calculate 30-day mortality
mortality AS (
  SELECT a.hadm_id, 
         CASE WHEN a.deathtime <= DATETIME_ADD(a.admittime, INTERVAL 30 DAY) THEN 1 ELSE 0 END AS died_within_30_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN dka_patients ON a.hadm_id = dka_patients.hadm_id
),

-- Step 3: Calculate mean risk score (using SAPS-II as an example)
-- This part is simplified and assumes relevant data is available in chartevents
-- Detailed SAPS-II calculation is complex and not fully implemented here
sapsii_components AS (
  SELECT ce.stay_id, 
         -- Example components; actual calculation is more complex
         MAX(CASE WHEN di.label = 'Heart Rate' THEN ce.valuenum END) AS hr,
         MAX(CASE WHEN di.label = 'Systolic Blood Pressure' THEN ce.valuenum END) AS sbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON ce.stay_id = icu.stay_id
  INNER JOIN dka_patients ON icu.hadm_id = dka_patients.hadm_id
  GROUP BY ce.stay_id
),
sapsii AS (
  SELECT icu.hadm_id,
         -- Simplified example; actual SAPS-II calculation involves more variables and logic
         AVG((ce.hr + ce.sbp)) AS sapsii_score
  FROM sapsii_components ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON ce.stay_id = icu.stay_id
  GROUP BY icu.hadm_id
),

-- Step 4 & 5: AKI and ARDS rates, Survivor LOS
aki_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  WHERE dl.label = 'Creatinine' AND l.valuenum > 1.2  -- Simplified AKI definition
  AND hadm_id IN (SELECT hadm_id FROM dka_patients)
),
ards_patients AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Acute respiratory distress syndrome%'
  AND d.hadm_id IN (SELECT hadm_id FROM dka_patients)
),
los AS (
  SELECT a.hadm_id, DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS length_of_stay
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN dka_patients ON a.hadm_id = dka_patients.hadm_id
  WHERE a.dischtime IS NOT NULL
)

-- Final aggregation
SELECT 
  AVG(s.sapsii_score) AS mean_sapsii,
  AVG(m.died_within_30_days) AS thirty_day_mortality,
  COUNT(DISTINCT a.hadm_id) / COUNT(DISTINCT dka_patients.hadm_id) AS aki_rate,
  COUNT(DISTINCT ards.hadm_id) / COUNT(DISTINCT dka_patients.hadm_id) AS ards_rate,
  PERCENTILE_CONT(l.length_of_stay, 0.5) AS median_los
FROM dka_patients
LEFT JOIN sapsii s ON dka_patients.hadm_id = s.hadm_id
LEFT JOIN mortality m ON dka_patients.hadm_id = m.hadm_id
LEFT JOIN aki_patients a ON dka_patients.hadm_id = a.hadm_id
LEFT JOIN ards_patients ards ON dka_patients.hadm_id = ards.hadm_id
LEFT JOIN los l ON dka_patients.hadm_id = l.hadm_id;