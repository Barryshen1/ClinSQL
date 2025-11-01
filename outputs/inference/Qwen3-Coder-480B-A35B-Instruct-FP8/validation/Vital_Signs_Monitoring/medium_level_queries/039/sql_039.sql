WITH cohort AS (
  SELECT
    i.stay_id,
    i.subject_id,
    i.intime,
    i.outtime
  FROM
    physionet-data.mimiciv_3_1_icu.icustays i
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
  ON
    i.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
),

map_items AS (
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_icu.d_items
  WHERE LOWER(label) = 'map'
),

map_measurements AS (
  SELECT
    c.stay_id,
    c.intime,
    ce.charttime,
    ce.valuenum AS map_value
  FROM
    cohort c
  JOIN
    physionet-data.mimiciv_3_1_icu.chartevents ce
  ON
    c.stay_id = ce.stay_id
  JOIN
    map_items mi
  ON
    ce.itemid = mi.itemid
  WHERE
    ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
),

stay_averages AS (
  SELECT
    stay_id,
    AVG(map_value) AS avg_map,
    COUNT(*) AS measurement_count
  FROM
    map_measurements
  GROUP BY
    stay_id
  HAVING
    COUNT(*) >= 3
),

percentile_data AS (
  SELECT
    avg_map,
    PERCENT_RANK() OVER (ORDER BY avg_map) AS percentile_rank
  FROM
    stay_averages
)

SELECT
  APPROX_QUANTILES(percentile_rank, 100)[OFFSET(50)] AS median_percentile,
  MAX(CASE WHEN avg_map <= 60 THEN percentile_rank END) AS percentile_of_60
FROM
  percentile_data
CROSS JOIN
  (SELECT 60 AS target_map);