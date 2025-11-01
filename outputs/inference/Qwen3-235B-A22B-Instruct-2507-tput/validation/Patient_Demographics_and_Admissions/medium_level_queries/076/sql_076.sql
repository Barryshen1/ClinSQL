WITH patient_los AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) >= 0
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 83 AND 93
),
summary_stats AS (
  SELECT
    hospital_expire_flag,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS median_los,
    APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS p75_los,
    APPROX_QUANTILES(los_days, 1000)[OFFSET(900)] AS p90_los,
    SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_rank_5day
  FROM
    patient_los
  GROUP BY
    hospital_expire_flag
)
SELECT
  hospital_expire_flag,
  mean_los,
  median_los,
  p75_los,
  p90_los,
  ROUND(percentile_rank_5day, 4) AS percentile_rank_5day
FROM
  summary_stats
ORDER BY
  hospital_expire_flag;