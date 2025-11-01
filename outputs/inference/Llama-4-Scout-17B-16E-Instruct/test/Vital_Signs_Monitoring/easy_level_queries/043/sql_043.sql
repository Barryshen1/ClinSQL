WITH 
-- Define the population of interest
patients_of_interest AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 77 AND 87
),

-- Find the itemid for GCS total
gcs_itemid AS (
  SELECT 
    itemid 
  FROM 
    `physionet-data.mimiciv_3_1_icu.d_items` 
  WHERE 
    label = 'Glasgow Coma Scale'
),

-- First recorded GCS for each ICU stay
first_gcs AS (
  SELECT 
    ic.stay_id,
    MIN(cv.charttime) AS first_charttime,
    cv.value
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` cv 
      ON ic.subject_id = cv.subject_id 
      AND ic.hadm_id = cv.hadm_id 
      AND ic.stay_id = cv.stay_id
  JOIN 
    gcs_itemid gi 
      ON cv.itemid = gi.itemid
  WHERE 
    ic.subject_id IN (SELECT subject_id FROM patients_of_interest)
  GROUP BY 
    ic.stay_id, cv.value
)

-- Calculate the average first recorded GCS
SELECT 
  AVG(CAST(value AS INT64)) AS avg_first_gcs
FROM 
  first_gcs;