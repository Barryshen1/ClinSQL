SELECT
  APPROX_QUANTILES(
    DATETIME_DIFF(stoptime, starttime, HOUR), 100
  )[OFFSET(25)] AS percentile_25_duration_hours
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` p
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON p.subject_id = pat.subject_id
WHERE
  LOWER(p.drug) LIKE '%amiodarone%'
  AND pat.gender = 'F'
  AND pat.anchor_age BETWEEN 42 AND 52
  AND p.starttime IS NOT NULL
  AND p.stoptime IS NOT NULL;