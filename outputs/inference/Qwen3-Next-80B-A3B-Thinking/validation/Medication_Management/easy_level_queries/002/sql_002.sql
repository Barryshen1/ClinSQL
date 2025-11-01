WITH durations AS (
  SELECT
    DATE_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON
    p.subject_id = pt.subject_id
  WHERE
    pt.gender = 'F'
    AND pt.anchor_age BETWEEN 59 AND 69
    AND LOWER(p.drug) = 'amiodarone'
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
)
SELECT
  PERCENTILE_CONT(duration_days, 0.75) OVER () - PERCENTILE_CONT(duration_days, 0.25) OVER () AS iqr
FROM durations
LIMIT 1;