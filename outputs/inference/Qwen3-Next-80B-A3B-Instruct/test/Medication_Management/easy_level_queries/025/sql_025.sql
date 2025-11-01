WITH amiodarone_prescriptions AS (
  SELECT
    p.stoptime,
    p.starttime,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, SECOND) / 86400.0 AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON p.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 62 AND 72
    AND LOWER(p.drug) LIKE '%amiodarone%'
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
),
iqr_calc AS (
  SELECT
    PERCENTILE_CONT(duration_days, 0.25) OVER () AS q1,
    PERCENTILE_CONT(duration_days, 0.75) OVER () AS q3
  FROM
    amiodarone_prescriptions
)
SELECT
  q3 - q1 AS iqr_days
FROM
  iqr_calc
LIMIT 1;