WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age >= 60 AND anchor_age <= 70
),
Prescriptions AS (
  SELECT
    rx.subject_id,
    rx.drug,
    rx.dose_val_rx,
    rx.dose_unit_rx,
    rx.starttime,
    rx.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS rx
  JOIN PatientInfo AS pi
    ON rx.subject_id = pi.subject_id
  WHERE
    rx.drug = 'atorvastatin' AND CAST(rx.dose_val_rx AS INT64) >= 40 AND CAST(rx.dose_val_rx AS INT64) <= 80 AND rx.dose_unit_rx = 'mg'
)
SELECT
  PERCENTILE_CONT(0.25, duration) AS IQR_25,
  PERCENTILE_CONT(0.75, duration) AS IQR_75
FROM (
  SELECT
    subject_id,
    (
      CASE
        WHEN stoptime IS NULL
        THEN TIMESTAMP_DIFF(starttime, CURRENT_TIMESTAMP(), DAY)
        ELSE TIMESTAMP_DIFF(stoptime, starttime, DAY)
      END
    ) AS duration
  FROM Prescriptions
);