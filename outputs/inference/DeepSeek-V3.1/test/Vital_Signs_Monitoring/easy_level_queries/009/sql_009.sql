WITH temp_events AS (
  SELECT 
    ce.subject_id,
    ce.stay_id,
    -- Convert Celsius to Fahrenheit if needed, otherwise use as is
    CASE 
      WHEN ce.valueuom = 'C' THEN (ce.valuenum * 9/5) + 32
      ELSE ce.valuenum
    END AS temp_f
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie 
    ON ce.stay_id = ie.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ce.subject_id = p.subject_id
  WHERE 
    -- Female patients aged 86-96
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 86 AND 96
    -- Temperature itemids (Fahrenheit and Celsius)
    AND ce.itemid IN (223761, 223762) 
    -- Within first 24 hours of ICU stay
    AND ce.charttime >= ie.intime
    AND ce.charttime <= DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
    -- Only numeric values
    AND ce.valuenum IS NOT NULL
)
SELECT 
  PERCENTILE_CONT(temp_f, 0.75) OVER() AS percentile_75_temp_f
FROM temp_events
LIMIT 1;