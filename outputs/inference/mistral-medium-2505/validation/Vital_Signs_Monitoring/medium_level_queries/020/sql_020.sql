WITH
-- Get female patients aged 58-68
female_patients AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 58 AND 68
),

-- Get their ICU stays
female_icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    female_patients p ON s.subject_id = p.subject_id
),

-- Get MAP measurements (assuming itemid 220050 is MAP)
map_measurements AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.valuenum AS map_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` d ON c.itemid = d.itemid
  WHERE
    d.label = 'Mean Arterial Pressure'
    AND c.valuenum IS NOT NULL
),

-- Calculate 48-hour mean MAP for each stay
stay_mean_map AS (
  SELECT
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    s.anchor_age,
    AVG(m.map_value) AS mean_map_48h,
    COUNT(m.map_value) AS map_count
  FROM
    female_icu_stays s
  LEFT JOIN
    map_measurements m ON s.stay_id = m.stay_id
    AND m.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
  GROUP BY
    s.stay_id, s.subject_id, s.hadm_id, s.anchor_age
  HAVING
    map_count > 0  -- Only include stays with at least one MAP measurement
),

-- Calculate percentiles
percentiles AS (
  SELECT
    mean_map_48h,
    PERCENT_RANK() OVER (ORDER BY mean_map_48h) AS percentile
  FROM
    stay_mean_map
)

-- Final result showing the percentile for 85 mmHg
SELECT
  ROUND(MAX(percentile) * 100, 2) AS percentile_for_85_mmHg
FROM
  percentiles
WHERE
  mean_map_48h <= 85;