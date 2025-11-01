WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 82 AND 92
), ICUStays AS (
  SELECT
    s.subject_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS s
  JOIN
    PatientAge AS pa
    ON s.subject_id = pa.subject_id
), TemperatureEvents AS (
  SELECT
    s.subject_id,
    s.stay_id,
    s.intime, -- Added intime here
    c.charttime,
    c.valuenum AS temperature
  FROM
    ICUStays AS s
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS c
    ON s.subject_id = c.subject_id AND s.stay_id = c.stay_id
  WHERE
    c.itemid = 220187 -- Temperature Celsius
), First24HoursTemperature AS (
  SELECT
    subject_id,
    stay_id,
    temperature
  FROM
    TemperatureEvents
  WHERE
    charttime BETWEEN intime AND TIMESTAMP_ADD(intime, INTERVAL 24 HOUR)
), AvgTemperature AS (
  SELECT
    subject_id,
    stay_id,
    AVG(temperature) AS avg_temperature
  FROM
    First24HoursTemperature
  GROUP BY
    subject_id,
    stay_id
)
SELECT
  PERCENTILE_CONT(avg_temperature, 0.5) AS median_avg_temperature
FROM
  AvgTemperature;