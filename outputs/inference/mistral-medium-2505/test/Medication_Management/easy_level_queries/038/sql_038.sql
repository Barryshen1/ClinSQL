WITH digoxin_prescriptions AS (
  SELECT
    p.subject_id,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS prescription_duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    pr.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
    AND LOWER(pr.drug) LIKE '%digoxin%'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
)

SELECT
  PERCENTILE_CONT(prescription_duration_days, 0.25) OVER() AS q1,
  PERCENTILE_CONT(prescription_duration_days, 0.5) OVER() AS median,
  PERCENTILE_CONT(prescription_duration_days, 0.75) OVER() AS q3,
  PERCENTILE_CONT(prescription_duration_days, 0.75) OVER() -
    PERCENTILE_CONT(prescription_duration_days, 0.25) OVER() AS iqr
FROM
  digoxin_prescriptions
LIMIT 1;