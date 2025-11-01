WITH patient_ages AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.discharge_location,
    a.hospital_expire_flag,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit,
    -- Compute LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND a.admission_type IN ('URGENT', 'EMERGENCY')
),
cohort AS (
  SELECT *
  FROM patient_ages
  WHERE age_at_admit >= 37 AND age_at_admit <= 47
    AND los_days >= 0  -- Ensure valid LOS
),
discharge_groups AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location IN ('HOME', 'HOME WITH HOME HEALTH', 'HOME HEALTH CARE') THEN 'Home'
      ELSE 'Facility'
    END AS discharge_outcome
  FROM cohort
),
stats_per_group AS (
  SELECT
    discharge_outcome,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 1000)[OFFSET(250)] AS p25_los,
    APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS p50_los,
    APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS p75_los,
    -- Compute cumulative distribution to get percentile rank of 7-day stay
    APPROX_QUANTILES(
      CASE WHEN los_days <= 7 THEN 1 ELSE 0 END,  -- dummy for cume_dist logic
      1000
    )[OFFSET(500)] AS dummy  -- placeholder; instead, use ARRAY_AGG and UNNEST
  FROM discharge_groups
  GROUP BY discharge_outcome
),
-- Recompute percentile rank of 7-day stay using CUME_DIST via window function
percentile_ranks AS (
  SELECT
    discharge_outcome,
    -- Use CUME_DIST to compute fraction of stays <= 7 days
    SAFE_DIVIDE(
      COUNTIF(los_days <= 7),
      COUNT(*)
    ) AS percentile_rank_of_7day
  FROM discharge_groups
  GROUP BY discharge_outcome
)
-- Final select with all metrics
SELECT
  s.discharge_outcome,
  ROUND(s.mean_los, 2) AS mean_los,
  ROUND(s.p25_los, 2) AS p25_los,
  ROUND(s.p50_los, 2) AS p50_los,
  ROUND(s.p75_los, 2) AS p75_los,
  ROUND(p.percentile_rank_of_7day * 100, 1) AS percentile_rank_of_7day_pct
FROM stats_per_group s
JOIN percentile_ranks p
  ON s.discharge_outcome = p.discharge_outcome
ORDER BY
  CASE discharge_outcome
    WHEN 'Home' THEN 1
    WHEN 'Facility' THEN 2
    WHEN 'In-hospital death' THEN 3
  END;