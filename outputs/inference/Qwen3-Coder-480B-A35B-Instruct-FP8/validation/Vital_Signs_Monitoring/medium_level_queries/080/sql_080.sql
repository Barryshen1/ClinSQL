WITH cohort AS (
  SELECT
    icu.stay_id,
    icu.intime,
    icu.outtime,
    pat.gender,
    pat.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON
    icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 56 AND 66
),

map_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'map'
),

map_values AS (
  SELECT
    ce.stay_id,
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    cohort co
  ON
    ce.stay_id = co.stay_id
  JOIN
    map_items mi
  ON
    ce.itemid = mi.itemid
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.charttime >= co.intime
    AND ce.charttime <= DATETIME_ADD(co.intime, INTERVAL 48 HOUR)
),

stay_mean_map AS (
  SELECT
    stay_id,
    AVG(valuenum) AS mean_map
  FROM
    map_values
  GROUP BY
    stay_id
),

categorized AS (
  SELECT
    stay_id,
    mean_map,
    CASE
      WHEN mean_map < 65 THEN '<65'
      WHEN mean_map >= 65 AND mean_map < 75 THEN '65–74'
      WHEN mean_map >= 75 AND mean_map < 85 THEN '75–84'
      WHEN mean_map >= 85 THEN '≥85'
    END AS map_category
  FROM
    stay_mean_map
)

SELECT
  map_category,
  COUNT(*) AS stay_count,
  AVG(mean_map) AS mean_mean_map,
  APPROX_QUANTILES(mean_map, 2)[OFFSET(1)] AS median_mean_map,
  APPROX_QUANTILES(mean_map, 4)[OFFSET(1)] AS q1_mean_map,
  APPROX_QUANTILES(mean_map, 4)[OFFSET(3)] AS q3_mean_map,
  APPROX_QUANTILES(mean_map, 4)[OFFSET(3)] - APPROX_QUANTILES(mean_map, 4)[OFFSET(1)] AS iqr_mean_map
FROM
  categorized
GROUP BY
  map_category
ORDER BY
  CASE map_category
    WHEN '<65' THEN 1
    WHEN '65–74' THEN 2
    WHEN '75–84' THEN 3
    WHEN '≥85' THEN 4
  END;