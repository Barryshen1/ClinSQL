WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    subject_id IN (
      SELECT DISTINCT
        subject_id
      FROM
        `physionet-data.mimiciv_3_1_icu.icustays`
    )
), ICUStayInfo AS (
  SELECT
    icustays.subject_id,
    icustays.hadm_id,
    icustays.stay_id,
    icustays.intime,
    icustays.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
), SpO2Measurements AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    icustays.intime,
    chartevents.charttime,
    chartevents.value AS spo2_value
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS chartevents
      ON icustays.stay_id = chartevents.stay_id
  WHERE
    chartevents.itemid = 5061 -- SpO2 itemid
    AND chartevents.value IS NOT NULL
    AND chartevents.valuenum IS NOT NULL
), First24HoursSpO2 AS (
  SELECT
    spo2.subject_id,
    spo2.stay_id,
    spo2.charttime,
    spo2.spo2_value
  FROM
    SpO2Measurements AS spo2
    INNER JOIN ICUStayInfo AS icustays
      ON spo2.subject_id = icustays.subject_id
        AND spo2.stay_id = icustays.stay_id
  WHERE
    spo2.charttime >= icustays.intime
    AND spo2.charttime < TIMESTAMP_ADD(icustays.intime, INTERVAL 24 HOUR)
), PatientMeanSpO2 AS (
  SELECT
    subject_id,
    stay_id,
    AVG(CAST(spo2_value AS NUMERIC)) AS mean_spo2
  FROM
    First24HoursSpO2
  GROUP BY
    subject_id,
    stay_id
), TargetPatientSpO2 AS (
  SELECT
    patient_mean_spo2.mean_spo2
  FROM
    PatientMeanSpO2 AS patient_mean_spo2
    INNER JOIN PatientInfo AS patients
      ON patient_mean_spo2.subject_id = patients.subject_id
  WHERE
    patients.gender = 'M'
    AND patients.anchor_age BETWEEN 73 AND 83
    AND patient_mean_spo2.mean_spo2 = 92
)
SELECT
  PERCENTILE_CONT(0.5, patient_mean_spo2.mean_spo2) AS median_spo2
FROM
  PatientMeanSpO2 AS patient_mean_spo2;