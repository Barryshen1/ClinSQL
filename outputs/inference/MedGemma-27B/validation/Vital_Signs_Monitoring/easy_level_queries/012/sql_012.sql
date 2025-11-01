WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 49 AND 59
), PatientStays AS (
  SELECT
    p.subject_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.first_careunit,
    i.last_careunit
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN
    PatientAge AS p
    ON i.subject_id = p.subject_id
  WHERE
    i.first_careunit IN ('STEPDOWN', 'IMC')
), DiastolicBP AS (
  SELECT
    ps.stay_id,
    AVG(ce.valuenum) AS mean_diastolic_bp
  FROM
    PatientStays AS ps
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ps.stay_id = ce.stay_id
  WHERE
    ce.itemid = 456 -- Diastolic Blood Pressure
  GROUP BY
    ps.stay_id
)
SELECT
  PERCENTILE_CONT(mean_diastolic_bp, 0.25) AS q1,
  PERCENTILE_CONT(mean_diastolic_bp, 0.75) AS q3,
  PERCENTILE_CONT(mean_diastolic_bp, 0.75) - PERCENTILE_CONT(mean_diastolic_bp, 0.25) AS iqr
FROM
  DiastolicBP;