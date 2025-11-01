WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age >= 80 AND anchor_age < 90
), PrescriptionInfo AS (
  SELECT
    rx.subject_id,
    rx.drug AS nitrate_drug,
    rx.starttime AS prescription_start,
    rx.stoptime AS prescription_stop,
    rx.route AS administration_route
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS rx
  JOIN PatientInfo AS pi
    ON rx.subject_id = pi.subject_id
  WHERE
    rx.drug LIKE '%nitrate%'
    AND rx.route IN ('IV', 'PO', 'SL')
)
SELECT
  MAX(TIMESTAMP_DIFF(prescription_stop, prescription_start, HOUR)) AS max_duration_hours
FROM PrescriptionInfo;