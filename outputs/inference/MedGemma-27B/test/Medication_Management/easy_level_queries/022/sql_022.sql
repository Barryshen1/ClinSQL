WITH PatientInfo AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 59 AND 69
), PrescriptionInfo AS (
  SELECT
    p.subject_id,
    p.starttime,
    p.stoptime,
    p.drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  JOIN
    PatientInfo AS pi
    ON p.subject_id = pi.subject_id
  WHERE
    p.drug LIKE '%dihydropyridine%'
    AND p.drug LIKE '%CCB%'
), DurationCalculation AS (
  SELECT
    subject_id,
    -- Calculate the duration of each prescription in hours
    TIMESTAMP_DIFF(stoptime, starttime, HOUR) AS duration_hours
  FROM
    PrescriptionInfo
)
SELECT
  PERCENTILE_CONT(duration_hours, 0.5) WITHIN GROUP (ORDER BY duration_hours) AS median_duration_hours
FROM
  DurationCalculation;