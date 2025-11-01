WITH female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 59 AND 69
),

amiodarone_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    female_patients fp ON p.subject_id = fp.subject_id
  WHERE
    LOWER(p.drug) = 'amiodarone'
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
    AND TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) > 0
)

SELECT
  PERCENTILE_CONT(duration_days, 0.25) OVER() AS q1,
  PERCENTILE_CONT(duration_days, 0.5) OVER() AS median,
  PERCENTILE_CONT(duration_days, 0.75) OVER() AS q3,
  PERCENTILE_CONT(duration_days, 0.75) OVER() - PERCENTILE_CONT(duration_days, 0.25) OVER() AS iqr
FROM
  amiodarone_prescriptions
LIMIT 1;