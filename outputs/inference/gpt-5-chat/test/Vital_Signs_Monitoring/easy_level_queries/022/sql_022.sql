WITH cohort AS (
  SELECT 
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 48 AND 58
),
map_events AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohort c
    ON ce.stay_id = c.stay_id
  WHERE ce.itemid IN (220052, 220181)  -- Invasive and NIBP mean arterial pressure
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
),
max_map_per_stay AS (
  SELECT
    stay_id,
    MAX(valuenum) AS max_map
  FROM map_events
  GROUP BY stay_id
)
SELECT
  AVG(max_map) AS avg_of_max_map
FROM max_map_per_stay;