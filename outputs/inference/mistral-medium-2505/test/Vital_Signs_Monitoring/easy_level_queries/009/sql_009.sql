WITH female_icu_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year_group,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
),

temperature_readings AS (
  SELECT
    f.subject_id,
    f.stay_id,
    c.charttime,
    c.valuenum AS temp_celsius,
    c.valuenum * 9/5 + 32 AS temp_fahrenheit
  FROM
    female_icu_patients f
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON f.subject_id = c.subject_id AND f.stay_id = c.stay_id
  WHERE
    c.itemid = 223761  -- Temperature in Celsius
    AND c.valuenum IS NOT NULL
    AND c.charttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 24 HOUR)
)

SELECT
  PERCENTILE_CONT(temp_fahrenheit, 0.75) OVER() AS percentile_75_temp_f
FROM
  temperature_readings
LIMIT 1;