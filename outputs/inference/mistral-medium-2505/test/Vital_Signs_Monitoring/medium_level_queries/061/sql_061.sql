WITH
-- Get male patients aged 38-48
male_patients_38_48 AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 38 AND 48
),

-- Get their ICU stays
icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    male_patients_38_48 p
  ON
    i.subject_id = p.subject_id
),

-- Get MAP measurements (itemid 220050 is MAP)
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
    icu_stays i
  ON
    c.subject_id = i.subject_id
    AND c.hadm_id = i.hadm_id
    AND c.stay_id = i.stay_id
  WHERE
    c.itemid = 220050  -- MAP itemid
    AND c.valuenum IS NOT NULL
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
  HAVING
    COUNT(map_value) > 0  -- Only stays with at least one MAP measurement
)

-- Calculate percentile rank for MAP = 60
SELECT
  COUNT(CASE WHEN avg_map <= 60 THEN 1 END) * 100.0 / COUNT(*) AS percentile_rank
FROM
  avg_map_per_stay;