WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    subject_id = 92 -- Specific patient ID
), ICUStays AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    icustays.intime,
    icustays.outtime,
    patients.gender,
    patients.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icustays -- Alias added
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS patients -- Alias added
    ON icustays.subject_id = patients.subject_id
  WHERE
    patients.gender = 'F' AND patients.anchor_age BETWEEN 87 AND 97
), SpO2Measurements AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    icustays.intime,
    icustays.outtime,
    chartevents.charttime,
    chartevents.value AS spo2_value
  FROM
    ICUStays -- Use alias
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS chartevents
    ON icustays.subject_id = chartevents.subject_id AND icustays.stay_id = chartevents.stay_id
  WHERE
    chartevents.itemid = 5061 -- SpO2 itemid
    AND chartevents.charttime BETWEEN icustays.intime AND icustays.outtime
    AND chartevents.charttime < TIMESTAMP_ADD(icustays.intime, INTERVAL 24 HOUR)
), First24HourAvgSpO2 AS (
  SELECT
    stay_id,
    AVG(spo2_value) AS avg_spo2_first_24h
  FROM
    SpO2Measurements
  GROUP BY
    stay_id
)
SELECT
  PERCENTILE_CONT(avg_spo2_first_24h, 0.5) AS median_avg_spo2_first_24h
FROM
  First24HourAvgSpO2;