WITH filtered_patients AS (
  -- Get male patients aged 52-62
  SELECT p.subject_id, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
),
first_map_per_stay AS (
  -- For each ICU stay, get the first MAP measurement
  SELECT 
    ce.subject_id,
    ce.stay_id,
    ce.valuenum AS first_map,
    ROW_NUMBER() OVER (
      PARTITION BY ce.stay_id 
      ORDER BY ce.charttime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE ce.itemid IN (220052, 220181)  -- MAP item IDs
    AND ce.valuenum IS NOT NULL        -- Ensure numeric value exists
),
combined_data AS (
  -- Combine filtered patients with their first MAP
  SELECT f.first_map
  FROM first_map_per_stay f
  INNER JOIN filtered_patients p
    ON f.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON f.stay_id = icu.stay_id
  WHERE f.rn = 1  -- Only the first MAP per stay
),
quartiles AS (
  -- Calculate quartiles (Q1, Q3) and IQR
  SELECT 
    APPROX_QUANTILES(first_map, 100) AS arr
  FROM combined_data
)
SELECT 
  arr[OFFSET(25)] AS q25,  -- 25th percentile
  arr[OFFSET(75)] AS q75,  -- 75th percentile
  arr[OFFSET(75)] - arr[OFFSET(25)] AS iqr  -- IQR
FROM quartiles;