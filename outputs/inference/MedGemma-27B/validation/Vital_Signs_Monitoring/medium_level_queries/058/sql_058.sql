WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age = 43
    AND gender = 'F'
), ICUStays AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    icustays.intime,
    icustays.outtime,
    patients.anchor_age,
    patients.gender
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS patients
    ON icustays.subject_id = patients.subject_id
  WHERE
    patients.gender = 'F'
    AND patients.anchor_age BETWEEN 38 AND 48
), SystolicBP AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    icustays.intime,
    chartevents.charttime,
    chartevents.valuenum AS systolic_bp
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS chartevents
    ON icustays.stay_id = chartevents.stay_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` AS d_items
    ON chartevents.itemid = d_items.itemid
  WHERE
    d_items.label = 'Systolic blood pressure'
    AND chartevents.charttime BETWEEN icustays.intime AND TIMESTAMP_ADD(icustays.intime, INTERVAL 24 HOUR)
), AvgSystolicBP AS (
  SELECT
    subject_id,
    stay_id,
    AVG(systolic_bp) AS avg_systolic_bp
  FROM
    SystolicBP
  GROUP BY
    subject_id,
    stay_id
), PercentileCalculation AS (
  SELECT
    avg_systolic_bp,
    PERCENTILE_CONT(avg_systolic_bp, 0.5) OVER (PARTITION BY 1) AS median_avg_systolic_bp
  FROM
    AvgSystolicBP
)
SELECT
  avg_systolic_bp,
  median_avg_systolic_bp
FROM
  PercentileCalculation
WHERE
  avg_systolic_bp = 120;