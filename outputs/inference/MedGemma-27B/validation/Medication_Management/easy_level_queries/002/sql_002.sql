WITH AmiodaronePrescriptions AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    pr.starttime,
    pr.stoptime,
    pr.drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON p.subject_id = pr.subject_id
  WHERE
    pr.drug = 'amiodarone'
    AND pr.drug_type = 'Drug'
),
PrescriptionDurations AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    -- Calculate duration in days
    (
      DATETIME_DIFF(
        pr.stoptime,
        pr.starttime,
        DAY
      )
    ) AS duration_days
  FROM
    AmiodaronePrescriptions AS pr
  WHERE
    pr.stoptime IS NOT NULL
)
SELECT
  PERCENTILE_CONT(duration_days, 0.25) AS q1,
  PERCENTILE_CONT(duration_days, 0.75) AS q3
FROM
  PrescriptionDurations
WHERE
  gender = 'F'
  AND anchor_age BETWEEN 59 AND 69;