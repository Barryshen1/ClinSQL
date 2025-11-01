WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 54 AND 64
),
ICUStays AS (
  SELECT
    icustays.subject_id,
    icustays.hadm_id,
    icustays.stay_id,
    icustays.intime,
    icustays.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
  INNER JOIN PatientInfo
    ON icustays.subject_id = PatientInfo.subject_id
),
RRMeasurements AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    icustays.intime,
    chartevents.charttime,
    chartevents.value AS rr_value
  FROM
    ICUStays AS icustays
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS chartevents
    ON icustays.subject_id = chartevents.subject_id AND icustays.stay_id = chartevents.stay_id
  WHERE
    chartevents.itemid = 442 -- Respiratory Rate itemid
    AND chartevents.charttime BETWEEN icustays.intime AND TIMESTAMP_ADD(icustays.intime, INTERVAL 48 HOUR)
),
AverageRR AS (
  SELECT
    stay_id,
    AVG(rr_value) AS avg_rr,
    MEDIAN(rr_value) AS median_rr,
    PERCENTILE_CONT(rr_value, 0.25) AS iqr_25,
    PERCENTILE_CONT(rr_value, 0.75) AS iqr_75
  FROM
    RRMeasurements
  GROUP BY
    stay_id
)
SELECT
  CASE
    WHEN avg_rr < 12
    THEN '<12'
    WHEN avg_rr BETWEEN 12 AND 20
    THEN '12–20'
    WHEN avg_rr BETWEEN 21 AND 29
    THEN '21–29'
    ELSE '≥30'
  END AS rr_category,
  COUNT(stay_id) AS n,
  AVG(avg_rr) AS mean_rr,
  AVG(median_rr) AS median_rr,
  AVG(iqr_75 - iqr_25) AS iqr
FROM
  AverageRR
GROUP BY
  rr_category
ORDER BY
  rr_category;