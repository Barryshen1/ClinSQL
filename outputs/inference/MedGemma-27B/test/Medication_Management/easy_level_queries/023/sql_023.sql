WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 78 AND 88
),
PrescriptionInfo AS (
  SELECT
    p.subject_id,
    rx.starttime,
    rx.stoptime,
    rx.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS rx
  INNER JOIN PatientInfo AS p
    ON rx.subject_id = p.subject_id
  WHERE
    rx.drug LIKE '%ACE inhibitor%'
),
PrescriptionDuration AS (
  SELECT
    subject_id,
    DATE_DIFF(stoptime, starttime, DAY) AS duration_days
  FROM PrescriptionInfo
)
SELECT
  STDDEV(duration_days)
FROM PrescriptionDuration;