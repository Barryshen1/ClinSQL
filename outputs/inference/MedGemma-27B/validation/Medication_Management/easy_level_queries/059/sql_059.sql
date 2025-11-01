WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 38 AND 48
),
PrescriptionDuration AS (
  SELECT
    p.subject_id,
    pr.starttime,
    pr.stoptime,
    -- Calculate duration in days, adding 1 to include the start day
    (TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) + 1) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  JOIN
    PatientAge AS p
    ON pr.subject_id = p.subject_id
  WHERE
    -- Filter for ARB medications (case-insensitive)
    LOWER(pr.drug) LIKE '%arb%'
    -- Ensure stoptime is not NULL
    AND pr.stoptime IS NOT NULL
    -- Ensure starttime is not NULL
    AND pr.starttime IS NOT NULL
)
SELECT
  PERCENTILE_CONT(duration_days, 0.75) AS percentile_75
FROM
  PrescriptionDuration;