WITH
-- Get male patients aged 39-49
male_patients_39_49 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 39 AND 49
),

-- Get ICU stays for these patients
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
    male_patients_39_49 p ON s.subject_id = p.subject_id
),

-- Get MAP measurements in the first 24 hours of ICU stay
map_measurements AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS map_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    icu_stays s ON ce.subject_id = s.subject_id AND ce.hadm_id = s.hadm_id AND ce.stay_id = s.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE
    di.label = 'Mean Arterial Pressure'
    AND ce.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
),

-- Calculate average MAP per stay
avg_map_per_stay AS (
  SELECT
    stay_id,
    AVG(map_value) AS avg_map
  FROM
    map_measurements
  GROUP BY
    stay_id
),

-- Calculate percentiles for the average MAP values if data exists
percentiles AS (
  SELECT
    PERCENTILE_CONT(avg_map, 0.5) OVER() AS median_map,
    PERCENTILE_CONT(avg_map, 0.25) OVER() AS q1_map,
    PERCENTILE_CONT(avg_map, 0.75) OVER() AS q3_map,
    PERCENTILE_CONT(avg_map, 0.9) OVER() AS p90_map,
    PERCENTILE_CONT(avg_map, 0.95) OVER() AS p95_map,
    PERCENTILE_CONT(avg_map, 0.99) OVER() AS p99_map
  FROM
    avg_map_per_stay
  WHERE
    EXISTS (SELECT 1 FROM avg_map_per_stay)
  LIMIT 1
),

-- Calculate the percentile for a MAP of 75 mmHg if data exists
percentile_for_75 AS (
  SELECT
    CASE
      WHEN COUNT(*) > 0 THEN (SELECT COUNT(*) FROM avg_map_per_stay WHERE avg_map <= 75) / COUNT(*)
      ELSE NULL
    END AS percentile
  FROM
    avg_map_per_stay
  LIMIT 1
)

-- Combine all results
SELECT
  p.*,
  p75.percentile AS percentile_for_75
FROM
  percentiles p
CROSS JOIN
  percentile_for_75 p75;