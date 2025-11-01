WITH Cohort AS (
  SELECT
    icustays.stay_id,
    icustays.subject_id,
    icustays.intime,
    icustays.outtime,
    patients.gender,
    patients.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS patients
      ON icustays.subject_id = patients.subject_id
  WHERE
    patients.gender = 'F'
    AND patients.anchor_age BETWEEN 75 AND 85
),
BP_Measurements AS (
  SELECT
    Cohort.stay_id,
    chartevents.charttime,
    chartevents.valuenum AS systolic_bp
  FROM
    Cohort
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS chartevents
      ON Cohort.stay_id = chartevents.stay_id
  WHERE
    chartevents.itemid = 4070 -- Systolic Blood Pressure
    AND chartevents.charttime BETWEEN Cohort.intime AND DATETIME_ADD(Cohort.intime, INTERVAL 48 HOUR)
),
Mean_Systolic_BP AS (
  SELECT
    stay_id,
    AVG(systolic_bp) AS mean_systolic_bp
  FROM
    BP_Measurements
  GROUP BY
    stay_id
)
SELECT
  PERCENTILE_CONT(mean_systolic_bp, 0.5) AS median_mean_systolic_bp
FROM
  Mean_Systolic_BP
WHERE
  mean_systolic_bp = 140;