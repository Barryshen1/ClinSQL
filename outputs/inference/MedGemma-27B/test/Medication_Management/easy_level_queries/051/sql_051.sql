WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age = 91
),
RelevantPatients AS (
  SELECT
    p.subject_id
  FROM PatientInfo AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS rx
    ON p.subject_id = rx.subject_id
  WHERE
    rx.drug = 'digoxin'
),
PrescriptionDurations AS (
  SELECT
    rp.subject_id,
    rx.starttime,
    rx.stoptime,
    rx.hadm_id
  FROM RelevantPatients AS rp
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS rx
    ON rp.subject_id = rx.subject_id
  WHERE
    rx.drug = 'digoxin'
),
PatientAgeGroup AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 86 AND 96
),
FinalPrescriptions AS (
  SELECT
    pd.subject_id,
    pd.starttime,
    pd.stoptime,
    pd.hadm_id
  FROM PrescriptionDurations AS pd
  JOIN PatientAgeGroup AS pag
    ON pd.subject_id = pag.subject_id
)
SELECT
  PERCENTILE_CONT(0.25, duration) AS q1,
  PERCENTILE_CONT(0.75, duration) AS q3
FROM (
  SELECT
    hadm_id,
    (
      CASE
        WHEN stoptime IS NULL
        THEN TIMESTAMP_DIFF(starttime, CURRENT_TIMESTAMP(), DAY)
        ELSE TIMESTAMP_DIFF(stoptime, starttime, DAY)
      END
    ) AS duration
  FROM FinalPrescriptions
);