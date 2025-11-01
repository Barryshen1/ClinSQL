WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 3600) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND a.admission_type = 'TRANSFER'
    AND (
      LOWER(a.admission_location) LIKE '%transfer%'
      OR LOWER(a.admission_location) LIKE '%other%'
      OR LOWER(a.admission_location) LIKE '%acute care%'
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
),
grouped_stats AS (
  SELECT
    hospital_expire_flag,
    COUNT(*) OVER (PARTITION BY hospital_expire_flag) AS admission_count,
    PERCENTILE_CONT(los_days, 0.5) OVER (PARTITION BY hospital_expire_flag) AS los_p50,
    PERCENTILE_CONT(los_days, 0.75) OVER (PARTITION BY hospital_expire_flag) AS los_p75,
    PERCENTILE_CONT(los_days, 0.90) OVER (PARTITION BY hospital_expire_flag) AS los_p90,
    PERCENTILE_CONT(los_days, 0.95) OVER (PARTITION BY hospital_expire_flag) AS los_p95,
    AVG(CASE WHEN los_days <= 10 THEN 1.0 ELSE 0.0 END) OVER (PARTITION BY hospital_expire_flag) AS los_10day_percentile_rank
  FROM filtered_admissions
)
-- Select distinct because window functions repeat values
SELECT DISTINCT
  hospital_expire_flag,
  admission_count,
  ROUND(los_p50, 2) AS los_p50,
  ROUND(los_p75, 2) AS los_p75,
  ROUND(los_p90, 2) AS los_p90,
  ROUND(los_p95, 2) AS los_p95,
  ROUND(los_10day_percentile_rank * 100, 2) AS los_10day_percentile_rank_pct
FROM grouped_stats
ORDER BY hospital_expire_flag;