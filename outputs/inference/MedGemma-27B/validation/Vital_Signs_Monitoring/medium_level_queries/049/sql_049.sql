WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 38 AND 48
), ICUStays AS (
  SELECT
    icustays.stay_id,
    icustays.subject_id,
    icustays.intime,
    icustays.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE
    icustays.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientAge
    )
), SystolicBP AS (
  SELECT
    icustays.stay_id,
    chartevents.charttime,
    chartevents.valuenum AS systolic_bp
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS chartevents
  INNER JOIN
    ICUStays AS icustays
    ON chartevents.stay_id = icustays.stay_id
  WHERE
    chartevents.itemid = 455 -- Systolic Blood Pressure
    AND chartevents.charttime BETWEEN icustays.intime AND TIMESTAMP_ADD(icustays.intime, INTERVAL 48 HOUR)
), AvgSystolicBP AS (
  SELECT
    stay_id,
    AVG(systolic_bp) AS avg_systolic_bp
  FROM
    SystolicBP
  GROUP BY
    stay_id
), PercentileCalculation AS (
  SELECT
    avg_systolic_bp,
    PERCENTILE_CONT(avg_systolic_bp, 0.5) OVER (ORDER BY avg_systolic_bp) AS median_avg_systolic_bp
  FROM
    AvgSystolicBP
)
SELECT
  median_avg_systolic_bp
FROM
  PercentileCalculation
LIMIT 1;