WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 85 AND 95
), ICUStays AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    icustays.intime,
    icustays.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  INNER JOIN
    PatientInfo
    ON icustays.subject_id = PatientInfo.subject_id
), TemperatureMeasurements AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    chartevents.charttime,
    chartevents.value AS temperature_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents`
  INNER JOIN
    ICUStays
    ON chartevents.subject_id = icustays.subject_id AND chartevents.stay_id = icustays.stay_id
  WHERE
    chartevents.itemid IN (
      SELECT
        itemid
      FROM
        `physionet-data.mimiciv_3_1_icu.d_items`
      WHERE
        label = 'Temperature'
    )
), AverageTemperature AS (
  SELECT
    stay_id,
    AVG(CAST(temperature_value AS NUMERIC)) AS avg_temperature
  FROM
    TemperatureMeasurements
  GROUP BY
    stay_id
)
SELECT
  PERCENTILE_CONT(0.01) OVER (ORDER BY avg_temperature) AS percentile_rank_01,
  PERCENTILE_CONT(0.25) OVER (ORDER BY avg_temperature) AS percentile_rank_025,
  PERCENTILE_CONT(0.50) OVER (ORDER BY avg_temperature) AS percentile_rank_050,
  PERCENTILE_CONT(0.75) OVER (ORDER BY avg_temperature) AS percentile_rank_075,
  PERCENTILE_CONT(0.99) OVER (ORDER BY avg_temperature) AS percentile_rank_099
FROM
  AverageTemperature
WHERE
  avg_temperature = 36.0;