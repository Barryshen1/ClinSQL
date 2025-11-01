WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Compute LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND a.admission_type NOT IN ('EMERGENCY', 'URGENT')
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
),
cohort AS (
  SELECT *
  FROM patient_admissions
  WHERE age_at_admission BETWEEN 52 AND 62
),
percentiles AS (
  SELECT
    hospital_expire_flag,
    APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS p50_los,
    APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS p75_los,
    APPROX_QUANTILES(los_days, 1000)[OFFSET(900)] AS p90_los,
    APPROX_QUANTILES(los_days, 1000)[OFFSET(950)] AS p95_los,
    -- Compute percentile rank of 7 days
    SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS pct_rank_7_days
  FROM cohort
  GROUP BY hospital_expire_flag
)
SELECT
  hospital_expire_flag,
  p50_los,
  p75_los,
  p90_los,
  p95_los,
  ROUND(pct_rank_7_days * 100, 2) AS pct_rank_7_days_percent
FROM percentiles
ORDER BY hospital_expire_flag;