WITH 
  -- Identify temperature itemid
  temp_itemids AS (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_icu.d_items` 
    WHERE label LIKE '%temperature%'
  ),
  
  -- Filter patients and their ICU stays
  patients_stays AS (
    SELECT p.subject_id, p.anchor_age, p.gender, ic.stay_id, ic.intime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic 
      ON p.subject_id = ic.subject_id
    WHERE p.gender = 'M' AND p.anchor_age BETWEEN 46 AND 56
  ),
  
  -- Filter temperature measurements in the first 24 hours
  temp_measurements AS (
    SELECT cv.valuenum
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` cv
    JOIN patients_stays ps 
      ON cv.subject_id = ps.subject_id AND cv.stay_id = ps.stay_id
    JOIN temp_itemids ti 
      ON cv.itemid = ti.itemid
    WHERE cv.charttime BETWEEN ps.intime AND TIMESTAMP_ADD(ps.intime, INTERVAL 24 HOUR)
      AND cv.valuenum IS NOT NULL
  )

-- Calculate median temperature
SELECT 
  APPROX_QUANTILES(valuenum, 1000)[500] AS median_temp
FROM temp_measurements;