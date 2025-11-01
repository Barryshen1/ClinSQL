WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_type != 'EMERGENCY'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT
  hospital_expire_flag,
  APPROX_QUANTILES(los_days, 100)[OFFSET(49)] AS p50_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(74)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(89)] AS p90_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(94)] AS p95_los,
  SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percentile_rank_7days
FROM
  filtered_admissions
GROUP BY
  hospital_expire_flag
ORDER BY
  hospital_expire_flag;