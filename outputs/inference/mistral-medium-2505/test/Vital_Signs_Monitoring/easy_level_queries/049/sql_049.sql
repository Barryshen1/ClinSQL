WITH
-- Get ICU stays for males aged 85-95
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
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    s.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 85 AND 95
),

-- Get MAP measurements in the first 24 hours of each ICU stay
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
    icu_stays s
  ON
    c.subject_id = s.subject_id
    AND c.hadm_id = s.hadm_id
    AND c.stay_id = s.stay_id
  WHERE
    c.itemid = 220050  -- MAP itemid
    AND c.charttime BETWEEN s.intime AND DATETIME_ADD(s.intime, INTERVAL 24 HOUR)
),

-- Calculate mean MAP for each ICU stay
mean_map_per_stay AS (
  SELECT
    subject_id,
    stay_id,
    AVG(map_value) AS mean_map
  FROM
    map_measurements
  GROUP BY
    subject_id,
    stay_id
)

-- Calculate standard deviation of mean MAP across all stays
SELECT
  STDDEV(mean_map) AS stddev_first_24h_map
FROM
  mean_map_per_stay;