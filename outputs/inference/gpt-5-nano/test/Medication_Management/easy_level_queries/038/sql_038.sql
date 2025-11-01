WITH digoxin_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON p.subject_id = pat.subject_id
  WHERE LOWER(p.drug) LIKE '%digoxin%'
    AND pat.gender = 'Male'
    AND pat.anchor_age BETWEEN 36 AND 46
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
),
durations AS (
  SELECT
    (TIMESTAMP_DIFF(stoptime, starttime, SECOND) / 86400.0) AS duration_days
  FROM digoxin_prescriptions
  WHERE stoptime > starttime
)
SELECT
  q1_days,
  q3_days,
  (q3_days - q1_days) AS iqr_days
FROM (
  SELECT
    q[OFFSET(1)] AS q1_days,
    q[OFFSET(3)] AS q3_days
  FROM (
    SELECT APPROX_QUANTILES(duration_days, 4) AS q
    FROM durations
  )
);