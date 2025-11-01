SELECT
  a.hospital_expire_flag,
  COUNT(*) AS n,
  ROUND(AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)), 2) AS mean_los,
  APPROX_QUANTILES(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY), 100)[OFFSET(25)] AS los_p25,
  APPROX_QUANTILES(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY), 100)[OFFSET(50)] AS los_p50,
  APPROX_QUANTILES(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY), 100)[OFFSET(75)] AS los_p75,
  APPROX_QUANTILES(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY), 100)[OFFSET(90)] AS los_p90
FROM
  physionet-data.mimiciv_3_1_hosp.admissions a
JOIN
  physionet-data.mimiciv_3_1_hosp.patients p
ON
  a.subject_id = p.subject_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 44 AND 54
  AND a.admission_type = 'ELECTIVE'
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL
  -- Exclude negative LOS (shouldn't happen, but for safety)
  AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) >= 0
GROUP BY
  a.hospital_expire_flag
ORDER BY
  a.hospital_expire_flag;