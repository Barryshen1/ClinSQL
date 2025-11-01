WITH PatientHeartRate AS (
  SELECT
    subject_id,
    MAX(valuenum) AS max_heart_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE
    itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label = 'Heart Rate')
  GROUP BY
    subject_id
), PatientDemographics AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
)
SELECT
  PERCENTILE_CONT(0.25, max_heart_rate) AS iqr_25,
  PERCENTILE_CONT(0.75, max_heart_rate) AS iqr_75
FROM
  PatientHeartRate
JOIN
  PatientDemographics ON PatientHeartRate.subject_id = PatientDemographics.subject_id
WHERE
  gender = 'M' AND anchor_age BETWEEN 55 AND 65;