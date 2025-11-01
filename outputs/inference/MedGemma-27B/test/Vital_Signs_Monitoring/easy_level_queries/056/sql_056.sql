WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 46 AND 56
),
ICUStayInfo AS (
  SELECT
    p.subject_id,
    ic.stay_id,
    ic.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  JOIN
    PatientAge AS p
    ON ic.subject_id = p.subject_id
),
TemperatureEvents AS (
  SELECT
    ic.subject_id,
    ic.stay_id,
    ic.intime,
    ce.charttime,
    ce.value AS temperature_f
  FROM
    ICUStayInfo AS ic
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ic.subject_id = ce.subject_id AND ic.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220177 -- Temperature Fahrenheit
),
First24HoursTemperature AS (
  SELECT
    subject_id,
    stay_id,
    charttime,
    temperature_f
  FROM
    TemperatureEvents
  WHERE
    charttime BETWEEN intime AND TIMESTAMP_ADD(intime, INTERVAL 24 HOUR)
)
SELECT
  PERCENTILE_CONT(temperature_f, 0.5) AS median_temperature_f
FROM
  First24HoursTemperature;