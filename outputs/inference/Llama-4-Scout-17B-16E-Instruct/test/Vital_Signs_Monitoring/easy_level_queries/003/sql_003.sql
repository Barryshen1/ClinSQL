WITH 
  -- Filter patients and extract relevant data
  patients_data AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp`.patients p
    WHERE 
      p.gender = 'M' AND 
      p.anchor_age BETWEEN 40 AND 50
  ),

  -- Extract heart rate data
  heart_rate_data AS (
    SELECT 
      ce.subject_id,
      ce.hadm_id,
      ce.stay_id,
      ce.valuenum AS heart_rate
    FROM 
      `physionet-data.mimiciv_3_1_icu`.chartevents ce
    JOIN 
      `physionet-data.mimiciv_3_1_icu`.d_items di ON ce.itemid = di.itemid
    WHERE 
      di.label LIKE '%Heart Rate%' AND 
      ce.valuenum IS NOT NULL
  ),

  -- Join patients and heart rate data
  patient_heart_rate_data AS (
    SELECT 
      p.subject_id,
      hr.stay_id,
      hr.heart_rate
    FROM 
      patients_data p
    JOIN 
      heart_rate_data hr ON p.subject_id = hr.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_icu`.icustays i ON hr.stay_id = i.stay_id
  ),

  -- Calculate mean heart rate per stay
  mean_heart_rate_per_stay AS (
    SELECT 
      stay_id,
      AVG(heart_rate) AS mean_heart_rate
    FROM 
      patient_heart_rate_data
    GROUP BY 
      stay_id
  )

-- Calculate median of mean heart rates
SELECT 
  APPROX_QUANTILES(mean_heart_rate, 1000)[500] AS median_mean_heart_rate
FROM 
  mean_heart_rate_per_stay;