WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 40 AND 50
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
), HeartRateEvents AS (
  SELECT
    s.stay_id,
    c.charttime,
    c.valuenum AS heart_rate
  FROM
    ICUStays AS s
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS c
    ON s.stay_id = c.stay_id AND c.itemid = 220180 -- Heart Rate itemid
  WHERE
    c.valuenum IS NOT NULL
), StayMeanHeartRate AS (
  SELECT
    stay_id,
    AVG(heart_rate) AS mean_heart_rate
  FROM
    HeartRateEvents
  GROUP BY
    stay_id
)
SELECT
  PERCENTILE_CONT(mean_heart_rate, 0.5) AS median_mean_heart_rate
FROM
  StayMeanHeartRate;