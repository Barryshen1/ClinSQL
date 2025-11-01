WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE
    gender = 'M' AND anchor_age = 56
),
ICUStays AS (
  SELECT
    icustays.stay_id,
    icustays.subject_id
  FROM `physionet-data.mimiciv_3_1_icu`.icustays
  INNER JOIN PatientInfo
    ON icustays.subject_id = PatientInfo.subject_id
),
PotassiumMeasurements AS (
  SELECT
    icustays.stay_id,
    chartevents.charttime,
    chartevents.valuenum AS potassium_value,
    chartevents.valueuom AS potassium_unit
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents
  INNER JOIN ICUStays
    ON chartevents.stay_id = ICUStays.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items
    ON chartevents.itemid = d_items.itemid
  WHERE
    d_items.label = 'Potassium' AND chartevents.valueuom = 'mEq/L'
),
PeakPotassiumPerStay AS (
  SELECT
    stay_id,
    MAX(potassium_value) AS peak_potassium
  FROM PotassiumMeasurements
  GROUP BY
    stay_id
)
SELECT
  STDDEV(peak_potassium) AS std_dev_peak_potassium
FROM PeakPotassiumPerStay;