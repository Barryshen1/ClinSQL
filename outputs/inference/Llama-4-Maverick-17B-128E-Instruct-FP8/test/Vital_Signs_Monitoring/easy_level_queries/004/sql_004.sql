WITH 
-- Step 1: Filter patients and calculate age at ICU admission
relevant_patients AS (
  SELECT 
    p.subject_id,
    ie.stay_id,
    p.anchor_age + EXTRACT(YEAR FROM ie.intime) - p.anchor_year AS age_at_icu_admission
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ie ON p.subject_id = ie.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age + EXTRACT(YEAR FROM ie.intime) - p.anchor_year BETWEEN 37 AND 47
),

-- Step 2: Identify itemid for temperature
temperature_itemid AS (
  SELECT 
    itemid 
  FROM 
    `physionet-data.mimiciv_3_1_icu.d_items` 
  WHERE 
    label LIKE '%Temperature%'
    AND (unitname = '°C' OR unitname = '°F')  -- Adjust based on expected units
),

-- Step 3 & 4: Extract temperature data and calculate mean temperature per stay
mean_temperatures AS (
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS mean_temperature
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN 
    temperature_itemid ti ON ce.itemid = ti.itemid
  WHERE 
    ce.stay_id IN (SELECT stay_id FROM relevant_patients)
  GROUP BY 
    ce.stay_id
)

-- Step 5: Calculate the 75th percentile of mean temperatures
SELECT 
  APPROX_QUANTILES(mean_temperature, 100)[OFFSET(75)] AS percentile_75th
FROM 
  mean_temperatures;