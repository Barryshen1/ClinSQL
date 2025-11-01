WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age BETWEEN 66 AND 76
    AND gender = 'M'
), ICUStays AS (
  SELECT
    icustays.subject_id,
    icustays.hadm_id,
    icustays.stay_id,
    icustays.intime,
    icustays.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  INNER JOIN
    PatientInfo
    ON icustays.subject_id = PatientInfo.subject_id
), VentilatedStays AS (
  SELECT
    icustays.subject_id,
    icustays.hadm_id,
    icustays.stay_id,
    icustays.intime
  FROM
    ICUStays
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` -- Corrected table location
    ON icustays.hadm_id = emar.hadm_id
  WHERE
    emar.medication LIKE '%Ventilator%'
), SBPMeasurements AS (
  SELECT
    chartevents.subject_id,
    chartevents.hadm_id,
    chartevents.stay_id,
    chartevents.charttime,
    chartevents.valuenum AS systolic_bp
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents`
  INNER JOIN
    VentilatedStays
    ON chartevents.subject_id = VentilatedStays.subject_id
    AND chartevents.hadm_id = VentilatedStays.hadm_id
    AND chartevents.stay_id = VentilatedStays.stay_id
  WHERE
    chartevents.itemid = 220177 -- Systolic Blood Pressure
    AND chartevents.charttime BETWEEN VentilatedStays.intime AND TIMESTAMP_ADD(VentilatedStays.intime, INTERVAL 6 HOUR)
)
SELECT
  PERCENTILE_CONT(0.25, systolic_bp) AS iqr_25,
  PERCENTILE_CONT(0.75, systolic_bp) AS iqr_75
FROM
  SBPMeasurements;