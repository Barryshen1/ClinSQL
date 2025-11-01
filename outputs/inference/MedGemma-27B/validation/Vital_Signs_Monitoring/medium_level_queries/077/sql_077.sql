WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 42 AND 52
), ICUStays AS (
  SELECT
    ic.stay_id,
    ic.subject_id,
    ic.intime,
    ic.outtime,
    pa.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  JOIN
    PatientAge AS pa
    ON ic.subject_id = pa.subject_id
), HeartRate AS (
  SELECT
    ic.stay_id,
    AVG(ce.valuenum) AS avg_heart_rate
  FROM
    ICUStays AS ic
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ic.stay_id = ce.stay_id
    AND ce.itemid = 220177 -- Heart Rate
  GROUP BY
    ic.stay_id
)
SELECT
  COUNT(hr.stay_id) AS cohort_size,
  PERCENTILE_CONT(hr.avg_heart_rate, 0.5) AS median_heart_rate_percentile
FROM
  HeartRate AS hr;