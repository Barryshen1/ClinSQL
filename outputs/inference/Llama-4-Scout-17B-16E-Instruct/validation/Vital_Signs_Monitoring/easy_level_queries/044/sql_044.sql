WITH 
  -- Filter patients of interest
  patients_of_interest AS (
    SELECT subject_id, anchor_age, anchor_year, gender
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 82 AND 92
  ),
  
  -- Relevant admissions
  admissions_of_interest AS (
    SELECT a.hadm_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN patients_of_interest p ON a.subject_id = p.subject_id
  ),
  
  -- Relevant ICU stays
  icu_stays AS (
    SELECT i.stay_id, i.hadm_id, i.intime, i.outtime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN admissions_of_interest a ON i.hadm_id = a.hadm_id
  ),
  
  -- MAP events
  map_events AS (
    SELECT c.stay_id, c.charttime, c.valuenum
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
    WHERE c.itemid = 220050  -- Mean Arterial Pressure
  ),
  
  -- Maximum MAP per stay
  max_map_per_stay AS (
    SELECT stay_id, MAX(valuenum) AS max_map
    FROM map_events
    GROUP BY stay_id
  ),
  
  -- Join with ICU stays to link with hadm_id
  max_map_with_hadm AS (
    SELECT m.stay_id, i.hadm_id, m.max_map
    FROM max_map_per_stay m
    JOIN icu_stays i ON m.stay_id = i.stay_id
  )

-- Calculate median of maximum MAPs
SELECT 
  APPROX_QUANTILES(max_map, 100)[50] AS median_max_map
FROM max_map_with_hadm;