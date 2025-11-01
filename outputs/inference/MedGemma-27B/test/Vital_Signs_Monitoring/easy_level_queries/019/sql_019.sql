WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age = 78
),
ICUStayInfo AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    icustays.intime,
    icustays.outtime,
    icustays.first_careunit
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE
    icustays.first_careunit IN ('STEPDOWN', 'IMC')
),
MAPData AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    chartevents.charttime,
    chartevents.valuenum AS map_value
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS chartevents
    ON icustays.stay_id = chartevents.stay_id
  WHERE
    chartevents.itemid = 455
    AND chartevents.valuenum IS NOT NULL
)
SELECT
  AVG(map_value) AS average_map_per_stay
FROM
  MAPData
WHERE
  subject_id IN (
    SELECT
      subject_id
    FROM
      PatientInfo
  )
  AND stay_id IN (
    SELECT
      stay_id
    FROM
      ICUStayInfo
  )
  AND gender = 'F'
  AND anchor_age BETWEEN 73 AND 83;