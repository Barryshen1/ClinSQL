WITH AmiodaronePrescriptions AS (
  SELECT
    p.subject_id,
    rx.starttime,
    rx.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS rx
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON rx.subject_id = p.subject_id
  WHERE
    rx.drug = 'amiodarone'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 42 AND 52
),
PrescriptionDurations AS (
  SELECT
    TIMESTAMP_DIFF(stoptime, starttime, DAY) AS duration_days
  FROM AmiodaronePrescriptions
)
SELECT
  PERCENTILE_CONT(duration_days, 0.25) AS percentile_25
FROM PrescriptionDurations;