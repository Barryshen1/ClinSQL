SELECT
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] - APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS iqr_duration_days
FROM (
  SELECT
    DATETIME_DIFF(stoptime, starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON
    p.subject_id = pt.subject_id
  WHERE
    LOWER(p.drug) LIKE '%digoxin%'
    AND p.stoptime IS NOT NULL
    AND p.starttime IS NOT NULL
    AND p.starttime <= p.stoptime
    AND pt.gender = 'M'
    AND pt.anchor_age BETWEEN 36 AND 46
);