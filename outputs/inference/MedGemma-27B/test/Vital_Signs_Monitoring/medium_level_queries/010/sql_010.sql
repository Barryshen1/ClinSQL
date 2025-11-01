WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    subject_id = 82 -- Assuming 82 is the subject_id for the patient
), ICUStays AS (
  SELECT
    icustays.subject_id,
    icustays.hadm_id,
    icustays.stay_id,
    icustays.intime,
    icustays.outtime,
    patients.gender,
    patients.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icustays -- Alias icustays here
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS patients
    ON icustays.subject_id = patients.subject_id
  WHERE
    patients.gender = 'F'
    AND patients.anchor_age BETWEEN 77 AND 87
), SystolicBP AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    icustays.intime,
    chartevents.charttime,
    chartevents.valuenum AS systolic_bp
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icustays -- Alias icustays here
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS chartevents
    ON icustays.stay_id = chartevents.stay_id
  WHERE
    chartevents.itemid = 456 -- Systolic Blood Pressure (itemid 456)
    AND chartevents.charttime BETWEEN icustays.intime AND TIMESTAMP_ADD(icustays.intime, INTERVAL 48 HOUR)
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
)
SELECT
  PERCENTILE_CONT(avg_systolic_bp, 0.5) AS median_avg_systolic_bp
FROM
  AvgSystolicBP
WHERE
  avg_systolic_bp = 160;