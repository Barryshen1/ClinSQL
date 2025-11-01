WITH female_icu_cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 56 AND 66
),
map_events_first48 AS (
  SELECT
    c.stay_id,
    c.charttime,
    c.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN female_icu_cohort coh
    ON c.stay_id = coh.stay_id
  WHERE c.itemid IN (220052, 220181)  -- invasive/non-invasive MAP
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 0 AND c.valuenum < 200 -- plausibility filter
    AND c.charttime BETWEEN coh.intime AND coh.intime + INTERVAL 48 HOUR
),
mean_map_per_stay AS (
  SELECT
    stay_id,
    AVG(valuenum) AS mean_map
  FROM map_events_first48
  GROUP BY stay_id
),
categorized AS (
  SELECT
    stay_id,
    mean_map,
    CASE
      WHEN mean_map < 65 THEN '<65'
      WHEN mean_map >= 65 AND mean_map < 75 THEN '65-74'
      WHEN mean_map >= 75 AND mean_map < 85 THEN '75-84'
      ELSE '>=85'
    END AS map_category
  FROM mean_map_per_stay
)
SELECT
  map_category,
  COUNT(*) AS stay_count,
  ROUND(AVG(mean_map),2) AS mean_of_mean_map,
  ROUND( (APPROX_QUANTILES(mean_map, 100)[OFFSET(50)]), 2) AS median_mean_map,
  ROUND( (APPROX_QUANTILES(mean_map, 100)[OFFSET(75)] -
          APPROX_QUANTILES(mean_map, 100)[OFFSET(25)]), 2) AS iqr_mean_map
FROM categorized
GROUP BY map_category
ORDER BY map_category;