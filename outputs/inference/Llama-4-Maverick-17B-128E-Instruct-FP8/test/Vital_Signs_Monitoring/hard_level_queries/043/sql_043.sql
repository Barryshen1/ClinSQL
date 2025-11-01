WITH 
-- Step 1: Identify the cohort
cohort AS (
  SELECT a.subject_id, a.hadm_id, ie.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON a.hadm_id = ie.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 40 AND 50
),

-- Step 2: Identify patients with respiratory failure (simplified example)
respiratory_failure AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code IN ('J96.00', 'J96.01', 'J96.02', 'J96.90', 'J96.91', 'J96.92')  -- Example ICD codes for respiratory failure
),

-- Step 3: Extract relevant vital signs within the first 48 hours
vital_signs AS (
  SELECT c.stay_id, c.charttime, c.itemid, c.valuenum, 
         DATETIME_DIFF(c.charttime, ie.intime, HOUR) AS hours_since_icu_admit
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN cohort ON c.stay_id = cohort.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON c.stay_id = ie.stay_id
  WHERE c.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 48 HOUR)
  AND c.itemid IN ( -- Example itemids for vital signs
    220050,  -- Heart Rate
    220179,  -- Non-Invasive Blood Pressure mean
    220052   -- Temperature (not used but included for completeness)
  )
),

-- Step 4: Calculate VII, hypotensive, and tachycardic burden
vii_components AS (
  SELECT stay_id, 
         AVG(CASE WHEN itemid = 220050 THEN valuenum END) AS avg_hr,
         AVG(CASE WHEN itemid = 220179 THEN valuenum END) AS avg_map,
         COUNT(CASE WHEN itemid = 220050 AND valuenum > 100 THEN 1 END) AS tachycardic_count,
         COUNT(CASE WHEN itemid = 220179 AND valuenum < 65 THEN 1 END) AS hypotensive_count
  FROM vital_signs
  GROUP BY stay_id
),

-- Step 5: Calculate ICU LOS and mortality
outcomes AS (
  SELECT ie.stay_id, 
         DATETIME_DIFF(ie.outtime, ie.intime, HOUR) AS icu_los_hours,
         ie.hadm_id IN (SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.admissions` WHERE deathtime IS NOT NULL) AS hospital_mortality
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN cohort ON ie.stay_id = cohort.stay_id
)

-- Final analysis
SELECT 
  PERCENTILE_CONT(vii, 0.25) AS vii_25th,
  PERCENTILE_CONT(vii, 0.5) AS vii_50th,
  PERCENTILE_CONT(vii, 0.75) AS vii_75th,
  PERCENTILE_CONT(vii, 0.95) AS vii_95th,
  STDDEV(vii) AS vii_sd,
  
  AVG(CASE WHEN hypotensive_count > 0 THEN 1 ELSE 0 END) AS hypotensive_proportion,
  AVG(CASE WHEN tachycardic_count > 0 THEN 1 ELSE 0 END) AS tachycardic_proportion,
  
  AVG(icu_los_hours) AS avg_icu_los,
  AVG(CASE WHEN hospital_mortality THEN 1 ELSE 0 END) AS avg_hospital_mortality
FROM (
  SELECT vc.stay_id, 
         -- Simplified VII calculation for demonstration
         vc.avg_hr + vc.avg_map AS vii,
         vc.hypotensive_count,
         vc.tachycardic_count,
         o.icu_los_hours,
         o.hospital_mortality
  FROM vii_components vc
  JOIN outcomes o ON vc.stay_id = o.stay_id
  JOIN cohort c ON vc.stay_id = c.stay_id
  WHERE c.hadm_id IN (SELECT hadm_id FROM respiratory_failure)
) AS subquery;