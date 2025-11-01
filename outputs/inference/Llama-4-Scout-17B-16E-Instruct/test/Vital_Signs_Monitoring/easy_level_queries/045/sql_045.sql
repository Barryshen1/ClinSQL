WITH 
  -- Filter patients based on age and gender
  target_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M' AND anchor_age BETWEEN 51 AND 61
  ),
  
  -- Get first recorded respiratory rate for each patient in ICU
  first_respiratory_rate AS (
    SELECT 
      ce.valuenum AS first_respiratory_rate
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` icu ON ce.subject_id = icu.subject_id AND ce.hadm_id = icu.hadm_id
    WHERE 
      ce.itemid = 220050  -- Respiratory rate itemid
      AND ce.valuenum IS NOT NULL
      AND ce.subject_id IN (SELECT subject_id FROM target_patients)
      AND ce.charttime = (
        SELECT MIN(ce2.charttime)
        FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce2
        WHERE ce2.subject_id = ce.subject_id AND ce2.itemid = 220050
      )
  )

-- Calculate the standard deviation of the first recorded respiratory rates
SELECT 
  STDDEV(first_respiratory_rate) AS sd_first_respiratory_rate
FROM 
  first_respiratory_rate;