WITH cohort AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
),
map_measurements AS (
  SELECT
    ce.subject_id,
    ce.stay_id,
    ce.valuenum,
    ce.charttime,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN cohort c
    ON ce.subject_id = c.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.subject_id = icu.subject_id
   AND ce.stay_id = icu.stay_id
  WHERE ce.itemid = 220052 -- Mean Arterial Pressure
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= icu.intime
),
first_map_per_stay AS (
  SELECT *
  FROM map_measurements
  QUALIFY ROW_NUMBER() OVER (PARTITION BY stay_id ORDER BY charttime ASC) = 1
)
SELECT
  STDDEV_SAMP(valuenum) AS sd_first_map
FROM first_map_per_stay;