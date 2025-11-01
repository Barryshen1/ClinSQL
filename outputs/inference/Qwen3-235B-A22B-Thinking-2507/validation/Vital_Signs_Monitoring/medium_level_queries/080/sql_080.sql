WITH cohort AS (
  SELECT 
    stay.stay_id,
    stay.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` stay
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON stay.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND (
      pat.anchor_age + (EXTRACT(YEAR FROM stay.intime) - pat.anchor_year)
    ) BETWEEN 56 AND 66
),
map_measurements AS (
  SELECT 
    c.stay_id,
    ce.valuenum AS map_value
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.itemid IN (220052, 225312)  -- Standard MAP itemids
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
),
stay_mean_map AS (
  SELECT 
    stay_id,
    AVG(map_value) AS mean_map
  FROM map_measurements
  GROUP BY stay_id
),
categorized AS (
  SELECT 
    stay_id,
    mean_map,
    CASE 
      WHEN mean_map < 65 THEN '<65'
      WHEN mean_map < 75 THEN '65-74'
      WHEN mean_map < 85 THEN '75-84'
      ELSE '>=85'
    END AS category
  FROM stay_mean_map
)
SELECT
  category,
  COUNT(*) AS count,
  AVG(mean_map) AS mean_mean_map,
  APPROX_QUANTILES(mean_map, 1000)[OFFSET(500)] AS median,
  APPROX_QUANTILES(mean_map, 1000)[OFFSET(750)] - APPROX_QUANTILES(mean_map, 1000)[OFFSET(250)] AS iqr
FROM categorized
GROUP BY category
ORDER BY 
  CASE category
    WHEN '<65' THEN 1
    WHEN '65-74' THEN 2
    WHEN '75-84' THEN 3
    WHEN '>=85' THEN 4
  END;