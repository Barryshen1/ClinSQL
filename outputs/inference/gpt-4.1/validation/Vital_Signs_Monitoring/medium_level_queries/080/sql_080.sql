WITH map_itemids AS (
  -- List of MAP itemids in MIMIC-IV
  SELECT 220052 AS itemid UNION ALL
  SELECT 220181 UNION ALL
  SELECT 225312 UNION ALL
  SELECT 227243
),
female_icu_stays AS (
  -- Select ICU stays for female patients aged 56-66
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 56 AND 66
),
map_measurements AS (
  -- MAP measurements in first 48h of ICU stay
  SELECT
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN map_itemids mi ON ce.itemid = mi.itemid
    JOIN female_icu_stays fs ON ce.stay_id = fs.stay_id
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.charttime >= fs.intime
    AND ce.charttime < TIMESTAMP_ADD(fs.intime, INTERVAL 48 HOUR)
),
mean_map_per_stay AS (
  -- Calculate mean MAP per ICU stay
  SELECT
    stay_id,
    AVG(valuenum) AS mean_map
  FROM
    map_measurements
  GROUP BY
    stay_id
),
categorized_map AS (
  -- Categorize mean MAP
  SELECT
    stay_id,
    mean_map,
    CASE
      WHEN mean_map < 65 THEN '<65'
      WHEN mean_map >= 65 AND mean_map < 75 THEN '65-74'
      WHEN mean_map >= 75 AND mean_map < 85 THEN '75-84'
      WHEN mean_map >= 85 THEN '≥85'
      ELSE 'Unknown'
    END AS map_category
  FROM
    mean_map_per_stay
)
SELECT
  map_category,
  COUNT(*) AS stay_count,
  ROUND(AVG(mean_map), 2) AS mean_of_mean_map,
  ROUND(APPROX_QUANTILES(mean_map, 2)[OFFSET(1)], 2) AS median_of_mean_map,
  ROUND(APPROX_QUANTILES(mean_map, 4)[OFFSET(1)], 2) AS iqr_25,
  ROUND(APPROX_QUANTILES(mean_map, 4)[OFFSET(3)], 2) AS iqr_75
FROM
  categorized_map
WHERE
  map_category != 'Unknown'
GROUP BY
  map_category
ORDER BY
  -- Order by category in clinical order
  CASE map_category
    WHEN '<65' THEN 1
    WHEN '65-74' THEN 2
    WHEN '75-84' THEN 3
    WHEN '≥85' THEN 4
    ELSE 5
  END;