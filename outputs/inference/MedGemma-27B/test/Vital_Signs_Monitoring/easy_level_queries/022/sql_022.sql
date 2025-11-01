WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 48 AND 58
), ICUStays AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    icustays.intime,
    icustays.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  INNER JOIN
    PatientAge
    ON icustays.subject_id = PatientAge.subject_id
), MaxMAP AS (
  SELECT
    ICUStays.subject_id,
    ICUStays.stay_id,
    MAX(chartevents.valuenum) AS max_map
  FROM
    ICUStays
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents`
    ON ICUStays.subject_id = chartevents.subject_id AND ICUStays.stay_id = chartevents.stay_id
  WHERE
    chartevents.itemid = 455
  GROUP BY
    ICUStays.subject_id,
    ICUStays.stay_id
)
SELECT
  AVG(max_map) AS average_max_map
FROM
  MaxMAP;