WITH cohort AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    p.gender,
    p.anchor_age,
    ie.intime,
    ie.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
),
map_events AS (
  SELECT
    c.stay_id,
    ce.valuenum,
    ce.charttime
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.itemid IN (220052, 220181, 229314)  -- MAP itemids
    AND ce.valuenum IS NOT NULL
    AND ce.valueuom = 'mmHg'
    AND ce.charttime >= c.intime
    AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
),
avg_map_per_stay AS (
  SELECT
    stay_id,
    AVG(valuenum) AS avg_map,
    COUNT(*) AS num_measurements
  FROM map_events
  GROUP BY stay_id
  HAVING COUNT(*) >= 3
),
percentile_calc AS (
  SELECT
    100.0 * SUM(
      CASE 
        WHEN avg_map < 60 THEN 1
        WHEN avg_map = 60 THEN 0.5
        ELSE 0
      END
    ) / COUNT(*) AS percentile_60
  FROM avg_map_per_stay
)
SELECT percentile_60
FROM percentile_calc;