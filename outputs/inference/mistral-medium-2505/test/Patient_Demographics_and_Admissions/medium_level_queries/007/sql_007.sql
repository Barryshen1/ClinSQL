WITH
-- Get male patients aged 78-88 at admission who were transferred
transferred_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    -- Calculate age at admission (approximate)
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission,
    -- Calculate length of stay (in days)
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND a.admission_location LIKE '%TRANSFER%'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 78 AND 88
    AND a.dischtime IS NOT NULL  -- Only completed admissions
),

-- Calculate percentiles for each survival group
los_stats AS (
  SELECT
    hospital_expire_flag,
    COUNT(*) AS num_admissions,
    APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS p50,
    APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS p75,
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS p90,
    APPROX_QUANTILES(los_days, 100)[OFFSET(95)] AS p95
  FROM
    transferred_patients
  GROUP BY
    hospital_expire_flag
),

-- Calculate percentile rank for a 10-day LOS
los_percentile_rank AS (
  SELECT
    PERCENT_RANK() OVER (ORDER BY los_days) AS percentile_rank
  FROM
    transferred_patients
  WHERE
    los_days = 10
  LIMIT 1
)

-- Final output
SELECT
  'Survived' AS survival_status,
  num_admissions,
  p50,
  p75,
  p90,
  p95,
  (SELECT percentile_rank FROM los_percentile_rank) AS percentile_rank_for_10_day_los
FROM
  los_stats
WHERE
  hospital_expire_flag = 0

UNION ALL

SELECT
  'In-hospital Death' AS survival_status,
  num_admissions,
  p50,
  p75,
  p90,
  p95,
  (SELECT percentile_rank FROM los_percentile_rank) AS percentile_rank_for_10_day_los
FROM
  los_stats
WHERE
  hospital_expire_flag = 1
ORDER BY
  survival_status;