WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 39 AND 49
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
), HourlyMAP AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    icustays.intime,
    icustays.outtime,
    chartevents.charttime,
    chartevents.valuenum AS map_value
  FROM
    ICUStays
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS chartevents
    ON icustays.subject_id = chartevents.subject_id AND icustays.stay_id = chartevents.stay_id
  WHERE
    chartevents.itemid = 455 -- MAP
    AND chartevents.charttime BETWEEN icustays.intime AND TIMESTAMP_ADD(icustays.intime, INTERVAL 24 HOUR)
), First24HoursMAP AS (
  SELECT
    subject_id,
    stay_id,
    AVG(map_value) AS avg_map
  FROM
    HourlyMAP
  GROUP BY
    subject_id,
    stay_id
)
SELECT
  PERCENTILE_CONT(avg_map, 0.5) AS median_map
FROM
  First24HoursMAP;