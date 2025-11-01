WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
), ICUAdmission AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    icustays.intime AS icu_admission_time
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  INNER JOIN PatientInfo
    ON icustays.subject_id = PatientInfo.subject_id
), pHMeasurements AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    chartevents.charttime,
    chartevents.valuenum AS ph_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  INNER JOIN icustays
    ON chartevents.stay_id = icustays.stay_id
  WHERE
    chartevents.itemid = 50912 -- Arterial Blood Gas pH
)
SELECT
  PERCENTILE_CONT(0.5) OVER (PARTITION BY ICUAdmission.subject_id) AS median_ph
FROM ICUAdmission
INNER JOIN pHMeasurements
  ON ICUAdmission.subject_id = pHMeasurements.subject_id AND ICUAdmission.stay_id = pHMeasurements.stay_id
WHERE
  pHMeasurements.charttime = ICUAdmission.icu_admission_time;