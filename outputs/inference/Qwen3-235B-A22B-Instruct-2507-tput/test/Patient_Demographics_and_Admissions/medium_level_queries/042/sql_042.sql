WITH patient_los AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.admittime < a.dischtime
    AND a.admission_type != 'ELECTIVE'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 57 AND 67
),
medicine_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.services
  WHERE curr_service = 'MED'
),
cohort AS (
  SELECT
    pl.hadm_id,
    pl.hospital_expire_flag,
    pl.los_days
  FROM patient_los pl
  INNER JOIN medicine_patients m
    ON pl.hadm_id = m.hadm_id
),
stats AS (
  SELECT
    hospital_expire_flag,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS median_los,
    APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS p75_los,
    APPROX_QUANTILES(los_days, 1000)[OFFSET(900)] AS p90_los,
    -- Percentile rank of 5-day stay: fraction of patients with LOS <= 5
    SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS percentile_rank_5day
  FROM cohort
  GROUP BY hospital_expire_flag
)
SELECT
  hospital_expire_flag,
  ROUND(mean_los, 2) AS mean_los,
  ROUND(median_los, 2) AS median_los,
  ROUND(p75_los, 2) AS p75_los,
  ROUND(p90_los, 2) AS p90_los,
  ROUND(percentile_rank_5day, 3) AS percentile_rank_5day
FROM stats
ORDER BY hospital_expire_flag;