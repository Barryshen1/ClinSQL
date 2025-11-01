WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 67 AND 77
),
ICUStayInfo AS (
  SELECT
    icustays.subject_id,
    icustays.hadm_id,
    icustays.stay_id,
    icustays.intime,
    icustays.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
  INNER JOIN
    PatientAge
    ON icustays.subject_id = PatientAge.subject_id
),
HeartRateEvents AS (
  SELECT
    icustays.subject_id,
    icustays.hadm_id,
    icustays.stay_id,
    icustays.intime,
    chartevents.charttime,
    chartevents.valuenum AS heart_rate
  FROM
    ICUStayInfo AS icustays
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS chartevents
    ON icustays.subject_id = chartevents.subject_id
    AND icustays.hadm_id = chartevents.hadm_id
    AND icustays.stay_id = chartevents.stay_id
  WHERE
    chartevents.itemid = 220177 -- Heart Rate
),
First24HoursHR AS (
  SELECT
    subject_id,
    stay_id,
    heart_rate
  FROM
    HeartRateEvents
  WHERE
    charttime BETWEEN icustays.intime AND TIMESTAMP_ADD(icustays.intime, INTERVAL 24 HOUR) -- Corrected join condition
),
AvgHRPerStay AS (
  SELECT
    stay_id,
    AVG(heart_rate) AS avg_hr
  FROM
    First24HoursHR
  GROUP BY
    stay_id
)
SELECT
  PERCENTILE_CONT(avg_hr, 0.5) AS median_avg_hr
FROM
  AvgHRPerStay;