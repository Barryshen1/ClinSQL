WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 82 AND 92
), PrescriptionInfo AS (
  SELECT
    rx.subject_id,
    rx.hadm_id,
    rx.starttime,
    rx.stoptime,
    rx.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS rx
  JOIN PatientInfo AS pi
    ON rx.subject_id = pi.subject_id
  WHERE
    rx.drug = 'digoxin'
), DurationInfo AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    stoptime,
    -- Calculate duration in days
    DATE_DIFF(stoptime, starttime, DAY) AS duration_days
  FROM PrescriptionInfo
)
SELECT
  MAX(duration_days) AS longest_digoxin_prescription_duration_days
FROM DurationInfo;