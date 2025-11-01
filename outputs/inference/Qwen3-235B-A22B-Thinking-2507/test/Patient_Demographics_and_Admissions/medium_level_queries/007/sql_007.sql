WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND a.admission_location = 'TRANSFER FROM HOSPITAL'
    AND a.dischtime IS NOT NULL
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 78 AND 88
)
SELECT
  hospital_expire_flag AS status,
  COUNT(hadm_id) AS num_admissions,
  APPROX_QUANTILES(los_days, 10000)[OFFSET(5000)] AS p50,
  APPROX_QUANTILES(los_days, 10000)[OFFSET(7500)] AS p75,
  APPROX_QUANTILES(los_days, 10000)[OFFSET(9000)] AS p90,
  APPROX_QUANTILES(los_days, 10000)[OFFSET(9500)] AS p95,
  (SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) * 100.0) / COUNT(*) AS percentile_rank_10
FROM filtered_admissions
GROUP BY status
ORDER BY status;