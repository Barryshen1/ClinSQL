WITH female_icustays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 56 AND 66
),
map_events AS (
  SELECT
    fi.stay_id,
    ce.valuenum AS map_value
  FROM
    female_icustays AS fi
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON fi.subject_id = ce.subject_id
      AND fi.hadm_id    = ce.hadm_id
      AND fi.stay_id    = ce.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON ce.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%mean arterial pressure%'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN fi.intime
                        AND TIMESTAMP_ADD(fi.intime, INTERVAL 48 HOUR)
),
per_stay_mean_map AS (
  SELECT
    stay_id,
    AVG(map_value) AS mean_map
  FROM
    map_events
  GROUP BY
    stay_id
),
categorized AS (
  SELECT
    stay_id,
    mean_map,
    CASE
      WHEN mean_map < 65 THEN '<65'
      WHEN mean_map < 75 THEN '65–74'
      WHEN mean_map < 85 THEN '75–84'
      ELSE '>=85'
    END AS map_category
  FROM
    per_stay_mean_map
)
SELECT
  map_category,
  COUNT(*) AS stay_count,
  ROUND(AVG(mean_map), 2) AS mean_of_mean_map,
  -- median (approximate 50th percentile)
  APPROX_QUANTILES(mean_map, 100)[OFFSET(50)] AS median_map,
  -- IQR = Q3 - Q1 from quartiles
  (
    APPROX_QUANTILES(mean_map, 4)[OFFSET(3)]
    -
    APPROX_QUANTILES(mean_map, 4)[OFFSET(1)]
  ) AS iqr_map
FROM
  categorized
GROUP BY
  map_category
ORDER BY
  map_category;