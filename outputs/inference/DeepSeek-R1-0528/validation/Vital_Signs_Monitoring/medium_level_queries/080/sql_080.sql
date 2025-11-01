WITH eligible_stays AS (
  SELECT 
    icu.subject_id, 
    icu.stay_id, 
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year) + pat.anchor_age BETWEEN 56 AND 66
),
map_data AS (
  SELECT 
    fs.stay_id,
    ce.valuenum AS map_value
  FROM eligible_stays fs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fs.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (220052, 225312)  -- MAP item IDs
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= fs.intime
    AND ce.charttime <= DATETIME_ADD(fs.intime, INTERVAL 48 HOUR)
),
stay_mean_map AS (
  SELECT 
    stay_id,
    AVG(map_value) AS mean_map
  FROM map_data
  GROUP BY stay_id
  HAVING AVG(map_value) IS NOT NULL  -- Ensure valid mean
),
categorized AS (
  SELECT 
    stay_id,
    mean_map,
    CASE
      WHEN mean_map < 65 THEN '<65'
      WHEN mean_map BETWEEN 65 AND 74 THEN '65-74'
      WHEN mean_map BETWEEN 75 AND 84 THEN '75-84'
      WHEN mean_map >= 85 THEN '>=85'
    END AS map_category
  FROM stay_mean_map
),
aggregated AS (
  SELECT 
    map_category,
    COUNT(stay_id) AS stay_count,
    AVG(mean_map) AS mean_of_mean_map,
    APPROX_QUANTILES(mean_map, 4) AS quartiles  -- Returns [min, Q1, median, Q3, max]
  FROM categorized
  GROUP BY map_category
)
SELECT 
  map_category,
  stay_count,
  mean_of_mean_map,
  quartiles[SAFE_OFFSET(2)] AS median,  -- 50th percentile
  quartiles[SAFE_OFFSET(3)] - quartiles[SAFE_OFFSET(1)] AS iqr  -- Q3 - Q1
FROM aggregated
ORDER BY 
  CASE map_category
    WHEN '<65' THEN 1
    WHEN '65-74' THEN 2
    WHEN '75-84' THEN 3
    WHEN '>=85' THEN 4
  END;