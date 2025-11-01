WITH digoxin_durations AS (
  SELECT
    p.subject_id,
    DATETIME_DIFF(pr.stoptime, pr.starttime, HOUR) AS duration_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    pr.subject_id = p.subject_id
  WHERE
    LOWER(pr.drug) LIKE '%digoxin%'
    AND pr.stoptime IS NOT NULL
    AND pr.starttime IS NOT NULL
    AND pr.stoptime >= pr.starttime
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    AND pr.hadm_id IS NOT NULL
),
quartiles AS (
  SELECT
    APPROX_QUANTILES(duration_hours, 4) AS q
  FROM
    digoxin_durations
)
SELECT
  q[ORDINAL(3)] - q[ORDINAL(1)] AS iqr_duration_hours
FROM
  quartiles;