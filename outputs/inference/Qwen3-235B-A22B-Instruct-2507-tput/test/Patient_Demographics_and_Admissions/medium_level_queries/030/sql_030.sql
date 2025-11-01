SELECT
  hospital_expire_flag,
  COUNT(*) AS n,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(250)] AS p25_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS p50_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS p75_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(900)] AS p90_los
FROM (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) AS admittime_year,
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND a.admission_type = 'ELECTIVE'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 44 AND 54
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
WHERE
  los_days IS NOT NULL
  AND los_days >= 0
GROUP BY
  hospital_expire_flag
ORDER BY
  hospital_expire_flag;