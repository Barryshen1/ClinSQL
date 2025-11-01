WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age = 91
),
ICUStays AS (
  SELECT
    icustays.subject_id,
    icustays.hadm_id,
    icustays.stay_id,
    icustays.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
  INNER JOIN PatientInfo
    ON icustays.subject_id = PatientInfo.subject_id
  WHERE
    icustays.intime BETWEEN TIMESTAMP('2008-01-01 00:00:00') AND TIMESTAMP('2023-12-31 23:59:59')
),
TemperatureMeasurements AS (
  SELECT
    chartevents.stay_id,
    chartevents.charttime,
    chartevents.value AS temperature_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS chartevents
  INNER JOIN ICUStays
    ON chartevents.stay_id = ICUStays.stay_id
  WHERE
    chartevents.itemid = 220177 -- Temperature Fahrenheit
    AND chartevents.charttime BETWEEN ICUStays.intime AND TIMESTAMP_ADD(ICUStays.intime, INTERVAL 24 HOUR)
),
FilteredTemperatures AS (
  SELECT
    temperature_value
  FROM TemperatureMeasurements
  WHERE
    temperature_value IS NOT NULL
    AND temperature_value BETWEEN 80 AND 110 -- Reasonable temperature range in Fahrenheit
)
SELECT
  PERCENTILE_CONT(0.75, temperature_value) AS percentile_75_temperature
FROM FilteredTemperatures;