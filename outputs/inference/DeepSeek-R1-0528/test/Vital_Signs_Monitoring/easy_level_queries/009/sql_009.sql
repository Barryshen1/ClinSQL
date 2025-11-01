WITH cohort AS (
  SELECT
    ie.stay_id,
    ie.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
),
temp_measurements AS (
  SELECT
    ce.valuenum AS temperature
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE
    ce.itemid IN (223761, 223762)  -- Temperature Fahrenheit item IDs
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
)
SELECT
  APPROX_QUANTILES(temperature, 100)[OFFSET(75)] AS temperature_75th_percentile
FROM temp_measurements;