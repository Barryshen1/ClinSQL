WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 76 AND 86
),
PrescriptionDuration AS (
  SELECT
    p.subject_id,
    pr.drug,
    pr.starttime,
    pr.stoptime,
    -- Calculate duration in days
    (TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) + 1) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  INNER JOIN
    PatientAge AS p
    ON pr.subject_id = p.subject_id
  WHERE
    -- Filter for IV or oral nitrate prescriptions
    pr.route IN ('IV', 'PO') AND LOWER(pr.drug) LIKE '%nitrate%'
    AND pr.stoptime IS NOT NULL -- Ensure the prescription has an end time
)
SELECT
  PERCENTILE_CONT(duration_days, 0.25) AS percentile_25_duration
FROM
  PrescriptionDuration;