WITH 
  -- Filter patients by age and gender
  filtered_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 51 AND 61
  ),
  
  -- Identify ICU admissions
  icu_admissions AS (
    SELECT i.stay_id, i.subject_id, i.hadm_id, i.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN filtered_patients p ON i.subject_id = p.subject_id
  ),
  
  -- Find the first respiratory rate at ICU admission
  first_respiratory_rate AS (
    SELECT 
      icu.stay_id,
      cv.valuenum AS first_respiratory_rate
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` cv
    JOIN icu_admissions icu ON cv.stay_id = icu.stay_id
    WHERE cv.itemid = 220050  -- Respiratory rate itemid
      AND cv.charttime = (SELECT MIN(charttime) 
                          FROM `physionet-data.mimiciv_3_1_icu.chartevents` 
                          WHERE stay_id = icu.stay_id AND itemid = 220050)
  )

-- Calculate the 25th percentile of the first respiratory rates
SELECT 
  APPROX_QUANTILES(first_respiratory_rate, 25) AS percentile_25
FROM first_respiratory_rate;