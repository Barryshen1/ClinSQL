WITH temp_data AS (
  SELECT 
    ie.stay_id,
    -- Convert temperatures to Celsius
    CASE 
      WHEN ce.valueuom = 'F' THEN (ce.valuenum - 32) * 5.0/9.0
      WHEN ce.valueuom = 'C' THEN ce.valuenum
    END AS temp_c
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p  -- Fixed dataset
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce  -- Consistent ICU dataset
    ON ie.stay_id = ce.stay_id 
    AND ie.subject_id = ce.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di  -- Consistent ICU dataset
    ON ce.itemid = di.itemid
  WHERE 
    p.gender = 'F'
    AND di.category = 'Temperature'  -- Only temperature measurements
    AND ce.valuenum IS NOT NULL  -- Ensure numeric value exists
    AND ce.valueuom IN ('F', 'C')  -- Valid units
    -- Calculate age at ICU admission (anchor_age + years since anchor_year)
    AND p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) 
        BETWEEN 37 AND 47  -- Age filter
),
per_stay_avg AS (
  SELECT 
    stay_id,
    AVG(temp_c) AS mean_temp_c  -- Mean temperature per ICU stay
  FROM temp_data
  WHERE temp_c IS NOT NULL  -- Exclude conversion failures
  GROUP BY stay_id
)
-- Calculate 75th percentile of per-stay mean temperatures
SELECT 
  APPROX_QUANTILES(mean_temp_c, 100)[OFFSET(75)] AS percentile_75_temp_c
FROM per_stay_avg;