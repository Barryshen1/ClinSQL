WITH amiodarone_durations AS (
  SELECT
    p.hadm_id,
    DATETIME_DIFF(p.stoptime, p.starttime, DAY) AS duration
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON
    p.subject_id = pt.subject_id
  WHERE
    LOWER(p.drug) = 'amiodarone'
    AND p.drug_type = 'MAIN'
    AND p.hadm_id IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.starttime IS NOT NULL
    AND pt.gender = 'F'
    AND pt.anchor_age BETWEEN 59 AND 69
),
single_prescriptions AS (
  SELECT
    hadm_id,
    duration
  FROM
    amiodarone_durations
  GROUP BY
    hadm_id, duration
  HAVING
    COUNT(*) = 1
)
SELECT
  APPROX_QUANTILES(duration, 4)[OFFSET(3)] - APPROX_QUANTILES(duration, 4)[OFFSET(1)] AS iqr_duration_days
FROM
  single_prescriptions;