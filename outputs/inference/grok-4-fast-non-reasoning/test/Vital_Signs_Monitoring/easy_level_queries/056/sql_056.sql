WITH eligible_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
    AND i.los > 0
),
temperature_readings AS (
  SELECT ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN eligible_patients ep ON ce.subject_id = ep.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON (
    ce.subject_id = i.subject_id AND ce.stay_id = i.stay_id
  )
  WHERE ce.itemid IN (676, 677)
    AND ce.valuenum IS NOT NULL
    AND ce.valueuom = 'F'  -- Ensure Fahrenheit
    AND ce.charttime >= i.intime
    AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
)
SELECT
  PERCENTILE_CONT(valuenum, 0.5) OVER() AS median_temperature_f
FROM temperature_readings;