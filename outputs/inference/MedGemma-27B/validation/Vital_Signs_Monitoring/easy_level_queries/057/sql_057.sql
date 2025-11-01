WITH PatientDemographics AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
),
ICUStays AS (
  SELECT
    subject_id,
    stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
),
RespiratoryRateMeasurements AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    chartevents.charttime,
    chartevents.valuenum AS respiratory_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS chartevents
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
      ON chartevents.stay_id = icustays.stay_id
  WHERE
    chartevents.itemid = 220187 -- Respiratory Rate itemid
),
MaxRespiratoryRatePerStay AS (
  SELECT
    stay_id,
    MAX(respiratory_rate) AS max_respiratory_rate
  FROM
    RespiratoryRateMeasurements
  GROUP BY
    stay_id
),
FilteredPatients AS (
  SELECT
    subject_id
  FROM
    PatientDemographics
  WHERE
    gender = 'M' AND anchor_age BETWEEN 35 AND 45
)
SELECT
  MIN(max_respiratory_rate) AS min_of_max_respiratory_rate
FROM
  MaxRespiratoryRatePerStay
INNER JOIN
  FilteredPatients ON MaxRespiratoryRatePerStay.subject_id = FilteredPatients.subject_id;