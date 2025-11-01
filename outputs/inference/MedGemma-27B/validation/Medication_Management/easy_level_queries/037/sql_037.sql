WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age = 55
), PrescriptionDetails AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    pr.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  JOIN PatientInfo AS pi
    ON pr.subject_id = pi.subject_id
  WHERE
    pr.drug LIKE '%ACE inhibitor%'
), DurationCalculation AS (
  SELECT
    subject_id,
    hadm_id,
    -- Calculate duration in days
    (
      DATETIME_DIFF(stoptime, starttime, DAY)
    ) AS duration_days
  FROM PrescriptionDetails
)
SELECT
  PERCENTILE_CONT(duration_days, 0.25) AS percentile_25
FROM DurationCalculation;