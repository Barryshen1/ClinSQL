WITH 
  -- Identify itemid for arterial blood gas pH
  itemid_pH AS (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_icu.d_items` 
    WHERE label LIKE '%Arterial Blood Gas pH%'
  ),
  
  -- Select relevant chartevents for pH measurements on ICU admission
  pH_measurements AS (
    SELECT 
      ce.subject_id,
      ce.hadm_id,
      ce.stay_id,
      ce.charttime,
      ce.valuenum AS pH
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
    WHERE 
      ce.itemid IN (SELECT itemid FROM itemid_pH)
      AND ce.valuenum IS NOT NULL
  ),
  
  -- Filter for female patients and join with icustays for admission information
  female_patients AS (
    SELECT 
      p.subject_id,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE 
      p.gender = 'F'
  ),
  
  -- Combine information
  combined_info AS (
    SELECT 
      fp.subject_id,
      ci.stay_id,
      ci.intime AS icu_admit_time,
      pm.charttime,
      pm.pH
    FROM 
      female_patients fp
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ci ON fp.subject_id = ci.subject_id
    JOIN 
      pH_measurements pm ON fp.subject_id = pm.subject_id AND ci.stay_id = pm.stay_id
    WHERE 
      pm.charttime <= ci.intime + INTERVAL 1 HOUR  -- Consider pH within 1 hour of ICU admission
  )

-- Calculate median pH
SELECT 
  APPROX_QUANTILES(pH, 1000)[500] AS median_pH
FROM 
  combined_info;