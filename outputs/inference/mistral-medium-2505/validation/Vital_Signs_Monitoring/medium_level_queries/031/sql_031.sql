WITH male_icu_stays AS (
  -- Get male ICU stays for patients aged 67-77
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
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    s.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
),

temperature_measurements AS (
  -- Get temperature measurements within the first 24 hours of ICU stay
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.valuenum AS temperature_celsius
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    male_icu_stays s
  ON
    c.subject_id = s.subject_id
    AND c.hadm_id = s.hadm_id
    AND c.stay_id = s.stay_id
  WHERE
    -- Use itemid for temperature in Celsius (adjust if needed)
    c.itemid IN (223762) -- Temperature in Celsius
    AND c.charttime BETWEEN s.intime AND DATETIME_ADD(s.intime, INTERVAL 24 HOUR)
    AND c.valuenum IS NOT NULL
    AND c.valuenum BETWEEN 30 AND 42 -- Plausible range for body temperature
),

avg_temperature_per_stay AS (
  -- Calculate average temperature per stay
  SELECT
    stay_id,
    AVG(temperature_celsius) AS avg_temperature
  FROM
    temperature_measurements
  GROUP BY
    stay_id
)

-- Calculate the percentile of 36.0°C in the distribution of average temperatures
SELECT
  PERCENT_RANK() OVER (ORDER BY avg_temperature) AS percentile
FROM
  avg_temperature_per_stay
WHERE
  avg_temperature <= 36.0
ORDER BY
  avg_temperature DESC
LIMIT 1;