WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 80 AND 90
), ICUStays AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    icustays.intime,
    icustays.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  INNER JOIN
    PatientAge ON icustays.subject_id = PatientAge.subject_id
), SpO2Measurements AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    chartevents.charttime,
    chartevents.value AS spo2_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents`
  INNER JOIN
    ICUStays ON chartevents.stay_id = ICUStays.stay_id
  WHERE
    chartevents.itemid = 4070 -- SpO2 itemid
), AverageSpO2 AS (
  SELECT
    stay_id,
    AVG(CAST(spo2_value AS NUMERIC)) AS avg_spo2
  FROM
    SpO2Measurements
  GROUP BY
    stay_id
), PercentileCalculation AS (
  SELECT
    COUNT(stay_id) AS total_stays,
    COUNT(CASE WHEN avg_spo2 <= 88 THEN stay_id ELSE NULL END) AS stays_le_88
  FROM
    AverageSpO2
)
SELECT
  stays_le_88 / total_stays AS percentile
FROM
  PercentileCalculation;