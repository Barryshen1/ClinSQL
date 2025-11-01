WITH amiodarone_durations AS (
  SELECT
    DATETIME_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` pa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  USING
    (subject_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  USING
    (hadm_id)
  WHERE
    pa.gender = 'M'
    AND pa.anchor_age BETWEEN 62 AND 72
    AND LOWER(p.drug) LIKE '%amiodarone%'
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND (p.doses_per_24_hrs IS NULL OR p.doses_per_24_hrs <= 1)
)

SELECT
  APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] - APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS iqr
FROM
  amiodarone_durations
WHERE
  duration_days >= 0;