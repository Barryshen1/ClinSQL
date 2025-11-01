WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 81 AND 91
),
ICUStayInfo AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    icustays.intime,
    icustays.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE
    icustays.subject_id IN (
      SELECT
        subject_id
      FROM PatientInfo
    )
),
HFNCUsage AS (
  SELECT DISTINCT
    icustays.subject_id,
    icustays.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS procedureevents
    ON icustays.stay_id = procedureevents.stay_id
  WHERE
    icustays.subject_id IN (
      SELECT
        subject_id
      FROM PatientInfo
    )
    AND procedureevents.itemid = 226918 -- High-flow nasal cannula
),
SBPMeasurements AS (
  SELECT
    icustays.stay_id,
    chartevents.charttime,
    chartevents.valuenum AS systolic_bp
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS chartevents
    ON icustays.stay_id = chartevents.stay_id
  WHERE
    icustays.subject_id IN (
      SELECT
        subject_id
      FROM PatientInfo
    )
    AND chartevents.itemid = 455 -- Systolic blood pressure
)
SELECT
  HFNCUsage.stay_id,
  AVG(SBPMeasurements.systolic_bp) AS mean_systolic_bp
FROM HFNCUsage
JOIN SBPMeasurements
  ON HFNCUsage.stay_id = SBPMeasurements.stay_id
GROUP BY
  HFNCUsage.stay_id
ORDER BY
  mean_systolic_bp
LIMIT 1;