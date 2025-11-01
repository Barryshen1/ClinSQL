WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age = 43
),
ICUStayInfo AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    icustays.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
  INNER JOIN PatientInfo
    ON icustays.subject_id = PatientInfo.subject_id
),
RespiratoryRate AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    icustays.intime,
    chartevents.charttime,
    chartevents.valuenum AS respiratory_rate
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS chartevents
    ON icustays.stay_id = chartevents.stay_id
  WHERE
    chartevents.itemid = 220187 -- Respiratory Rate
    AND icustays.subject_id IN (
      SELECT
        subject_id
      FROM PatientInfo
    )
),
First24HoursRR AS (
  SELECT
    subject_id,
    stay_id,
    intime,
    charttime,
    respiratory_rate
  FROM RespiratoryRate
  WHERE
    charttime BETWEEN intime AND TIMESTAMP_ADD(intime, INTERVAL 24 HOUR)
)
SELECT
  MAX(respiratory_rate) AS max_respiratory_rate
FROM First24HoursRR;