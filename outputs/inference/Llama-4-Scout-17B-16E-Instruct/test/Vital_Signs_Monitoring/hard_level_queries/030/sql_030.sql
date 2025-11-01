WITH 
-- Step 1: Identify cohort
cohort AS (
  SELECT 
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON ic.hadm_id = a.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.anchor_age BETWEEN 43 AND 53
    AND ic.first_careunit LIKE '%ICU%'
    AND a.discharge_location LIKE '%ICU%'  
),

-- Step 2: Calculate vital instability index (for simplicity, let's assume it's based on heart rate and blood pressure)
vital_events AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    itemid,
    valuenum,
    valueuom
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE 
    itemid IN (220050, 220179, 220052)  
),

-- Step 3: Calculate vital instability index (95th percentile for the cohort)
vital_index AS (
  SELECT 
    stay_id,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(95)] AS vii_95th
  FROM 
    vital_events
  WHERE 
    itemid IN (220050, 220179, 220052)
  GROUP BY 
    stay_id
),

-- Step 4: Determine MAP < 65 hypotension and tachycardia episodes
map_tachycardia AS (
  SELECT 
    stay_id,
    COUNT(*) AS episodes
  FROM 
    vital_events
  WHERE 
    (itemid = 220179 AND valuenum < 65)  
    OR (itemid = 220050 AND valuenum > 100)  
  GROUP BY 
    stay_id
),

-- Step 5: ICU LOS and mortality
icu_outcomes AS (
  SELECT 
    ic.stay_id,
    TIMESTAMP_DIFF(ic.outtime, ic.intime, HOUR) / 24 AS icu_los,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 1
      ELSE 0
    END AS mortality
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON ic.hadm_id = a.hadm_id
)

-- Final query
SELECT 
  -- Cohort characteristics
  COUNT(DISTINCT c.stay_id) AS cohort_size,
  APPROX_QUANTILES(io.icu_los, 100)[OFFSET(25)] AS los_25th,
  APPROX_QUANTILES(io.icu_los, 100)[OFFSET(50)] AS los_median,
  APPROX_QUANTILES(io.icu_los, 100)[OFFSET(75)] AS los_75th,
  SUM(io.mortality) AS mortality_count,
  
  -- Compare to general ICU population
  (SELECT COUNT(DISTINCT stay_id) FROM `physionet-data.mimiciv_3_1_icu.icustays`) AS general_icu_population,
  (SELECT COUNT(DISTINCT i.stay_id) FROM `physionet-data.mimiciv_3_1_icu.icustays` i JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id WHERE a.hospital_expire_flag = 1) AS general_icu_mortality_count
FROM 
  cohort c
  JOIN vital_index vi ON c.stay_id = vi.stay_id
  JOIN map_tachycardia mt ON c.stay_id = mt.stay_id
  JOIN icu_outcomes io ON c.stay_id = io.stay_id;