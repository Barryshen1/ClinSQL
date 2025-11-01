WITH temp_measurements AS (
  -- Base CTE: Filter to female ICU patients aged 89-99, join to chartevents for temperatures
  SELECT 
    p.subject_id,
    i.stay_id,
    c.valuenum,
    c.itemid,
    -- Convert to Celsius, handling both units
    CASE 
      WHEN c.itemid = 676 THEN c.valuenum  -- Already Celsius
      WHEN c.itemid = 678 THEN (c.valuenum - 32) * 5.0 / 9  -- Fahrenheit to Celsius
      ELSE NULL 
    END AS temp_celsius
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.subject_id = c.subject_id 
    AND i.stay_id = c.stay_id
    AND c.charttime BETWEEN i.intime AND i.outtime  -- Ensure within ICU stay
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  WHERE 
    p.gender = 'F'
    AND EXTRACT(YEAR FROM i.intime) - p.anchor_year BETWEEN 89 AND 99  -- Age at ICU admission
    AND c.itemid IN (676, 678)  -- Temperature items
    AND d.category = 'Temperature'  -- Ensure correct category
    AND c.valuenum IS NOT NULL  -- Non-null values for conversion
),
valid_temps AS (
  -- Filter to plausible temperatures (15-45°C)
  SELECT 
    subject_id,
    temp_celsius
  FROM temp_measurements
  WHERE 
    temp_celsius IS NOT NULL
    AND temp_celsius >= 15
    AND temp_celsius <= 45
),
categorized_temps AS (
  -- Categorize temperatures
  SELECT 
    subject_id,
    temp_celsius,
    CASE 
      WHEN temp_celsius < 36 THEN '<36'
      WHEN temp_celsius >= 36 AND temp_celsius <= 37.9 THEN '36-37.9'
      WHEN temp_celsius >= 38 THEN '>=38'
      ELSE 'Missing/Invalid'
    END AS temp_category
  FROM valid_temps
),
all_temp_events AS (
  -- For MI rate: All temperature events (including unparseable valuenum)
  SELECT 
    i.subject_id
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.subject_id = c.subject_id 
    AND i.stay_id = c.stay_id
    AND c.charttime BETWEEN i.intime AND i.outtime
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  WHERE 
    p.gender = 'F'
    AND EXTRACT(YEAR FROM i.intime) - p.anchor_year BETWEEN 89 AND 99
    AND c.itemid IN (676, 678)
    AND d.category = 'Temperature'
),
agg_stats AS (
  SELECT 
    temp_category,
    COUNT(*) AS measurement_count,
    COUNT(DISTINCT subject_id) AS unique_patient_count,
    ROUND(AVG(temp_celsius), 2) AS mean_temp,
    PERCENTILE_CONT(temp_celsius, 0.5) OVER (PARTITION BY temp_category) AS median_temp,
    PERCENTILE_CONT(temp_celsius, 0.25) OVER (PARTITION BY temp_category) AS iqr_lower,
    PERCENTILE_CONT(temp_celsius, 0.75) OVER (PARTITION BY temp_category) AS iqr_upper,
    COUNT(*) AS valid_measurement_count
  FROM categorized_temps
  GROUP BY temp_category
),
totals AS (
  SELECT 
    COUNT(*) AS total_events,
    COUNT(DISTINCT subject_id) AS total_unique_patients
  FROM all_temp_events
)
SELECT 
  s.temp_category,
  s.mean_temp,
  s.median_temp,
  s.iar_lower,
  s.iqr_upper,
  s.measurement_count,
  s.unique_patient_count,
  ROUND(((t.total_events - s.valid_measurement_count) * 1.0 / t.total_events) * 100, 2) AS mi_rate_percent
FROM agg_stats s
CROSS JOIN totals t
ORDER BY 
  CASE s.temp_category
    WHEN '<36' THEN 1
    WHEN '36-37.9' THEN 2
    WHEN '>=38' THEN 3
  END;