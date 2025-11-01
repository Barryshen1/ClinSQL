WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Calculate LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) >= 0
    -- Age at admission between 57 and 67
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 57 AND 67
    -- ED admissions
    AND (
      LOWER(a.admission_location) LIKE '%emergency%'
      OR LOWER(a.admission_location) LIKE '%ed%'
    )
)
, labeled AS (
  SELECT
    *,
    CASE
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      ELSE NULL
    END AS discharge_group
  FROM cohort
)
, filtered AS (
  SELECT *
  FROM labeled
  WHERE discharge_group IS NOT NULL
)
, stats AS (
  SELECT
    discharge_group,
    COUNT(*) AS n_admissions,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 100)[SAFE_OFFSET(50)] AS median_los,
    APPROX_QUANTILES(los_days, 100)[SAFE_OFFSET(75)] AS p75_los,
    APPROX_QUANTILES(los_days, 100)[SAFE_OFFSET(90)] AS p90_los,
    -- Percentile rank for 10 days: proportion with LOS <= 10
    ROUND(100 * SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percentile_rank_10_days
  FROM filtered
  GROUP BY discharge_group
)
SELECT
  discharge_group,
  n_admissions,
  mean_los,
  median_los,
  p75_los,
  p90_los,
  percentile_rank_10_days
FROM stats
ORDER BY discharge_group;