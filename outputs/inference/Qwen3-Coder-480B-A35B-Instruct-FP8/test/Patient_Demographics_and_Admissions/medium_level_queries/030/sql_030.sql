SELECT
  hospital_expire_flag,
  COUNT(*) AS n,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS percentile_25,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS percentile_75,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS percentile_90
FROM (
  SELECT
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.admission_type = 'ELECTIVE'
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
) AS los_data
GROUP BY
  hospital_expire_flag
ORDER BY
  hospital_expire_flag;