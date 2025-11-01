WITH durations AS (
  SELECT
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  ON
    pat.subject_id = p.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 62 AND 72
    AND LOWER(p.drug) LIKE '%amiodarone%'
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) > 0
)
SELECT
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] - APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS iqr_days
FROM
  durations;