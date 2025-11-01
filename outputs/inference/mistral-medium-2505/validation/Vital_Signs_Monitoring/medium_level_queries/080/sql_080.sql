WITH
-- Get female patients aged 56-66
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 56 AND 66
),

-- Get their ICU stays
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    female_patients p ON s.subject_id = p.subject_id
),

-- Get MAP measurements in first 48 hours of each stay
map_measurements AS (
  SELECT
    s.stay_id,
    c.valuenum AS map_value,
    c.charttime
  FROM
    icu_stays s
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON s.subject_id = c.subject_id
    AND s.hadm_id = c.hadm_id
    AND s.stay_id = c.stay_id
  WHERE
    c.itemid IN (220050, 220051) -- MAP itemids
    AND c.valuenum IS NOT NULL
    AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
),

-- Calculate mean MAP per stay
stay_mean_map AS (
  SELECT
    stay_id,
    AVG(map_value) AS mean_map
  FROM
    map_measurements
  GROUP BY
    stay_id
  HAVING
    COUNT(map_value) > 0 -- Only stays with at least one MAP measurement
),

-- Categorize the mean MAP values
map_categories AS (
  SELECT
    stay_id,
    mean_map,
    CASE
      WHEN mean_map < 65 THEN '<65'
      WHEN mean_map BETWEEN 65 AND 74 THEN '65-74'
      WHEN mean_map BETWEEN 75 AND 84 THEN '75-84'
      ELSE '>=85'
    END AS map_category
  FROM
    stay_mean_map
)

-- Calculate statistics for each category
SELECT
  map_category,
  COUNT(stay_id) AS count,
  ROUND(AVG(mean_map), 2) AS mean,
  ROUND(PERCENTILE_CONT(mean_map, 0.5) OVER(), 2) AS median,
  ROUND(PERCENTILE_CONT(mean_map, 0.25) OVER(), 2) AS q1,
  ROUND(PERCENTILE_CONT(mean_map, 0.75) OVER(), 2) AS q3,
  ROUND(PERCENTILE_CONT(mean_map, 0.75) OVER() - PERCENTILE_CONT(mean_map, 0.25) OVER(), 2) AS iqr
FROM
  map_categories
GROUP BY
  map_category, stay_id, mean_map
ORDER BY
  CASE map_category
    WHEN '<65' THEN 1
    WHEN '65-74' THEN 2
    WHEN '75-84' THEN 3
    ELSE 4
  END;