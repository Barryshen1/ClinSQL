WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE
    gender = 'M' AND anchor_age = 90
), ICUStays AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    icustays.intime
  FROM `physionet-data.mimiciv_3_1_icu`.icustays
  INNER JOIN PatientInfo
    ON icustays.subject_id = PatientInfo.subject_id
), MAPValues AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    icustays.intime,
    chartevents.charttime,
    chartevents.valuenum AS map_value
  FROM icustays
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents
    ON icustays.subject_id = chartevents.subject_id AND icustays.stay_id = chartevents.stay_id
  WHERE
    chartevents.itemid = 455 -- MAP itemid
    AND chartevents.charttime BETWEEN icustays.intime AND icustays.intime + INTERVAL '24' HOUR
), First24HourMAP AS (
  SELECT
    subject_id,
    stay_id,
    intime,
    AVG(map_value) AS avg_map
  FROM MAPValues
  GROUP BY
    subject_id,
    stay_id,
    intime
)
SELECT
  STDDEV(avg_map)
FROM First24HourMAP
WHERE
  subject_id IN (
    SELECT
      subject_id
    FROM `physionet-data.mimiciv_3_1_hosp`.patients
    WHERE
      gender = 'M' AND anchor_age BETWEEN 85 AND 95
  );