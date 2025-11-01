WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 38 AND 48
), ICUStays AS (
  SELECT
    icustays.stay_id,
    icustays.subject_id,
    icustays.intime,
    icustays.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  INNER JOIN
    PatientAge
    ON icustays.subject_id = PatientAge.subject_id
), SpO2Measurements AS (
  SELECT
    icustays.stay_id,
    chartevents.charttime,
    chartevents.value AS spo2_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents`
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays`
    ON chartevents.stay_id = icustays.stay_id
  WHERE
    chartevents.itemid = 4070 -- SpO2 itemid
), MeanSpO2 AS (
  SELECT
    stay_id,
    AVG(CAST(spo2_value AS NUMERIC)) AS mean_spo2
  FROM
    SpO2Measurements
  GROUP BY
    stay_id
), SpO2Percentile AS (
  SELECT
    COUNT(stay_id) AS total_stays,
    COUNT(CASE WHEN mean_spo2 <= 92 THEN stay_id ELSE NULL END) AS stays_le_92
  FROM
    MeanSpO2
)
SELECT
  stays_le_92 / total_stays AS percentile
FROM
  SpO2Percentile;