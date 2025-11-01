WITH 
  -- Identify the itemid for respiratory rate
  respiratory_rate_itemid AS (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_icu.d_items` 
    WHERE label LIKE '%Respiratory Rate%'
  ),
  
  -- Extract respiratory rate data
  respiratory_rates AS (
    SELECT 
      ie.stay_id,
      ce.valuenum AS respiratory_rate
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ie 
      ON ce.subject_id = ie.subject_id AND ce.hadm_id = ie.hadm_id
    WHERE 
      ce.itemid IN (SELECT itemid FROM respiratory_rate_itemid)
      AND ce.valuenum IS NOT NULL
  ),
  
  -- Calculate mean respiratory rate per stay
  mean_respiratory_rates AS (
    SELECT 
      stay_id,
      AVG(respiratory_rate) AS mean_respiratory_rate
    FROM 
      respiratory_rates
    GROUP BY 
      stay_id
  ),
  
  -- Filter patients
  patients_info AS (
    SELECT 
      ie.subject_id,
      ie.hadm_id,
      ie.stay_id,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` ie
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON ie.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 39 AND 49
  ),
  
  -- Join patients with mean respiratory rates
  patient_respiratory_rates AS (
    SELECT 
      pir.stay_id,
      mrr.mean_respiratory_rate
    FROM 
      patients_info pir
    JOIN 
      mean_respiratory_rates mrr 
      ON pir.stay_id = mrr.stay_id
  )

-- Calculate 75th percentile of mean respiratory rates
SELECT 
  APPROX_QUANTILES(mean_respiratory_rate, 75)[OFFSET(1)] AS percentile_75
FROM 
  patient_respiratory_rates;