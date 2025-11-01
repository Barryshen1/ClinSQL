WITH 
-- Step 1: Identify female patients aged 59-69
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 59 AND 69
),

-- Step 2: Determine shock diagnosis
shock_diagnosis AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` USING (icd_code, icd_version)
  WHERE REGEXP_CONTAINS(long_title, r'(?i)shock')  -- Simplified shock diagnosis identification
),

-- Step 3 & 4: Extract ICU stay information and vital signs within the first 24 hours
icu_data AS (
  SELECT 
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.outtime,
    CASE WHEN sd.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS shock,
    -- Vital signs extraction
    -- Assuming itemid for MAP is known (e.g., 220052) and for heart rate (e.g., 220050)
    AVG(CASE WHEN ce.itemid = 220052 THEN ce.valuenum END) AS mean_map,
    SUM(CASE WHEN ce.itemid = 220052 AND ce.valuenum < 65 THEN 1 ELSE 0 END) / COUNT(*) AS hypotension_burden,
    SUM(CASE WHEN ce.itemid = 220050 AND ce.valuenum > 100 THEN 1 ELSE 0 END) / COUNT(*) AS tachycardia_burden
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  LEFT JOIN shock_diagnosis sd ON ie.hadm_id = sd.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ie.stay_id = ce.stay_id
    AND ce.charttime BETWEEN ie.intime AND TIMESTAMP_ADD(ie.intime, INTERVAL 24 HOUR)
  WHERE ie.subject_id IN (SELECT subject_id FROM eligible_patients)
  GROUP BY ie.subject_id, ie.hadm_id, ie.stay_id, ie.intime, ie.outtime, sd.hadm_id
),

-- Step 5: Compute ICU LOS and mortality
icu_outcomes AS (
  SELECT 
    i.stay_id,
    DATETIME_DIFF(i.outtime, i.intime, HOUR) / 24 AS icu_los,
    CASE 
      WHEN i.outtime = (SELECT MAX(outtime) FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE subject_id = i.subject_id) 
      AND (SELECT deathtime FROM `physionet-data.mimiciv_3_1_hosp.admissions` WHERE hadm_id = i.hadm_id) IS NOT NULL THEN 1 
      ELSE 0 
    END AS mortality
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
),

-- Step 6: Statistical analysis
final_data AS (
  SELECT 
    id.shock,
    id.hypotension_burden,
    id.tachycardia_burden,
    io.icu_los,
    io.mortality
  FROM icu_data id
  JOIN icu_outcomes io ON id.stay_id = io.stay_id
)

SELECT 
  shock,
  COUNT(*) AS n,
  AVG(hypotension_burden) AS mean_hypotension,
  APPROX_QUANTILES(hypotension_burden, 100)[OFFSET(25)] AS p25_hypotension,
  APPROX_QUANTILES(hypotension_burden, 100)[OFFSET(50)] AS median_hypotension,
  APPROX_QUANTILES(hypotension_burden, 100)[OFFSET(75)] AS p75_hypotension,
  AVG(tachycardia_burden) AS mean_tachycardia,
  APPROX_QUANTILES(tachycardia_burden, 100)[OFFSET(25)] AS p25_tachycardia,
  APPROX_QUANTILES(tachycardia_burden, 100)[OFFSET(50)] AS median_tachycardia,
  APPROX_QUANTILES(tachycardia_burden, 100)[OFFSET(75)] AS p75_tachycardia,
  AVG(icu_los) AS mean_icu_los,
  APPROX_QUANTILES(icu_los, 100)[OFFSET(25)] AS p25_icu_los,
  APPROX_QUANTILES(icu_los, 100)[OFFSET(50)] AS median_icu_los,
  APPROX_QUANTILES(icu_los, 100)[OFFSET(75)] AS p75_icu_los,
  AVG(mortality) AS mortality_rate
FROM final_data
GROUP BY shock;