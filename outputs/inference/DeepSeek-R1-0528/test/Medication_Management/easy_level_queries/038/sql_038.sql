WITH digoxin_prescriptions AS (
  SELECT
    DATETIME_DIFF(pr.stoptime, pr.starttime, HOUR) / 24.0 AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON p.subject_id = pr.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pr.hadm_id = a.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
    AND LOWER(pr.drug) LIKE '%digoxin%'
    AND pr.stoptime IS NOT NULL
    AND pr.starttime IS NOT NULL
    AND pr.stoptime > pr.starttime
)
SELECT
  approx_quantiles[OFFSET(1)] AS q1,
  approx_quantiles[OFFSET(3)] AS q3,
  approx_quantiles[OFFSET(3)] - approx_quantiles[OFFSET(1)] AS iqr
FROM (
  SELECT
    APPROX_QUANTILES(duration_days, 4) AS approx_quantiles
  FROM
    digoxin_prescriptions
);