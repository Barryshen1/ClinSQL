WITH male_inpatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.dischtime IS NOT NULL
    AND a.admittime < a.dischtime
)

SELECT
  CASE WHEN hospital_expire_flag = 0 THEN 'Alive' ELSE 'In-hospital Death' END AS status,
  COUNT(*) AS patient_count,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
  (SELECT PERCENT_RANK() OVER(ORDER BY los_days) FROM male_inpatients WHERE hospital_expire_flag = s.hospital_expire_flag AND los_days = 5 LIMIT 1) AS percentile_rank_5day_los
FROM
  male_inpatients s
GROUP BY
  hospital_expire_flag, status
ORDER BY
  hospital_expire_flag;