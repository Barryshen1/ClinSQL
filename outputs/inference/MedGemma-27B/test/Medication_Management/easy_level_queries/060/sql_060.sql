WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 38 AND 48
),
PrescriptionInfo AS (
  SELECT
    p.subject_id,
    p.starttime,
    p.stoptime,
    p.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  JOIN PatientInfo AS pi
    ON p.subject_id = pi.subject_id
  WHERE
    p.drug LIKE '%ACE inhibitor%'
),
DurationCalculation AS (
  SELECT
    subject_id,
    -- Calculate duration in days
    -- Use TIMESTAMP_DIFF to get the difference in seconds and divide by (60 * 60 * 24)
    (TIMESTAMP_DIFF(stoptime, starttime, SECOND) / (60 * 60 * 24)) AS duration_days
  FROM PrescriptionInfo
)
SELECT
  MAX(duration_days) AS longest_duration_days
FROM DurationCalculation;