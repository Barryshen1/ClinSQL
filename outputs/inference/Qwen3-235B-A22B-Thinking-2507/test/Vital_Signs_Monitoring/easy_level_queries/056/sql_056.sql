WITH cohort AS (
  SELECT 
    icu.stay_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year)) BETWEEN 46 AND 56
),
temperature_measurements AS (
  SELECT 
    ce.valuenum AS temperature_f
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE 
    ce.itemid = 223761  -- Temperature Fahrenheit
    AND ce.charttime >= c.intime
    AND ce.charttime <= c.intime + INTERVAL 24 HOUR
    AND ce.valuenum IS NOT NULL
)
SELECT 
  APPROX_QUANTILES(temperature_f, 1000)[OFFSET(500)] AS median_temperature_f
FROM temperature_measurements;