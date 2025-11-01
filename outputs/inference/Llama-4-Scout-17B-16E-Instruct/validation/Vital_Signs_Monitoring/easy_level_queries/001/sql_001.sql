WITH 
  -- Identify itemid for MAP
  map_itemid AS (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_icu.d_items` 
    WHERE label = 'Mean Arterial Pressure'
  ),
  
  -- Get first-recorded MAP for ICU patients
  first_map AS (
    SELECT 
      ie.subject_id,
      ie.hadm_id,
      ie.stay_id,
      ce.valuenum AS first_map_value
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` ie
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce 
        ON ie.subject_id = ce.subject_id 
        AND ie.hadm_id = ce.hadm_id 
        AND ie.stay_id = ce.stay_id
    JOIN 
      map_itemid mi 
        ON ce.itemid = mi.itemid
    WHERE ce.charttime = (SELECT MIN(charttime) 
                          FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce2 
                          WHERE ce2.subject_id = ie.subject_id 
                          AND ce2.hadm_id = ie.hadm_id 
                          AND ce2.stay_id = ie.stay_id 
                          AND ce2.itemid = mi.itemid)
  ),
  
  -- Filter by age and gender
  eligible_patients AS (
    SELECT 
      a.subject_id,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 52 AND 62
  )

-- Calculate IQR of first-recorded MAP
SELECT 
  APPROX_QUANTILES(first_map_value, 100)[25] AS Q1,
  APPROX_QUANTILES(first_map_value, 100)[75] AS Q3
FROM 
  first_map fm
JOIN 
  eligible_patients ep 
    ON fm.subject_id = ep.subject_id;