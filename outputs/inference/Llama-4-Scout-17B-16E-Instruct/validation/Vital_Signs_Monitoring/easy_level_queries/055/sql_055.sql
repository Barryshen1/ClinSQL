WITH 
-- Define SBP itemid
sbp_itemid AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_icu.d_items` 
  WHERE label LIKE '%Systolic Blood Pressure%'
),

-- Filter patients of interest
patients_of_interest AS (
  SELECT p.subject_id, p.anchor_age, p.gender, ic.stay_id, ic.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic 
    ON p.subject_id = ic.subject_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 76 AND 86
    AND ic.first_careunit LIKE '%STE%'  -- Assuming step-down/IMC units start with 'STE'
),

-- Get SBP measurements within the first 24 hours
sbp_measurements AS (
  SELECT poi.stay_id, 
         TIMESTAMP_DIFF(ce.charttime, poi.intime, HOUR) AS hours,
         ce.valuenum AS sbp
  FROM patients_of_interest poi
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON poi.stay_id = ce.stay_id
  JOIN sbp_itemid si 
    ON ce.itemid = si.itemid
  WHERE ce.valuenum IS NOT NULL 
    AND TIMESTAMP_DIFF(ce.charttime, poi.intime, HOUR) <= 24
)

-- Calculate SD of SBP
SELECT 
  STDDEV(sbp) AS std_dev_sbp
FROM sbp_measurements;