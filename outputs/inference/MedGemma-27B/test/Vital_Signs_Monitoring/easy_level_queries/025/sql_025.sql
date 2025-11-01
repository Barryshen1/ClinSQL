WITH PatientAgeGroup AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 39 AND 49
),
ICUStays AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
  INNER JOIN PatientAgeGroup AS pag
    ON icustays.subject_id = pag.subject_id
),
RespiratoryRate AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    AVG(chartevents.valuenum) AS mean_rr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS chartevents
  INNER JOIN ICUStays AS icustays
    ON chartevents.stay_id = icustays.stay_id
  WHERE
    chartevents.itemid = 220187 -- Respiratory Rate
  GROUP BY
    icustays.subject_id,
    icustays.stay_id
)
SELECT
  PERCENTILE_CONT(mean_rr, 0.75) AS percentile_75
FROM RespiratoryRate;