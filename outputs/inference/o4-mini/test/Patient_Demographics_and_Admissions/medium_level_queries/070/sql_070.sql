WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- LOS in days (fractional)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN UPPER(a.discharge_location) LIKE '%HOSPICE%' THEN 'Hospice'
      WHEN UPPER(a.discharge_location) LIKE 'HOME%' THEN 'Home'
      ELSE NULL
    END AS category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND a.admission_type = 'EMERGENCY'
),
stats AS (
  SELECT
    category,
    -- ARRAY of 101 quantiles (0th through 100th percentile)
    APPROX_QUANTILES(los_days, 100) AS qs,
    AVG(los_days) AS mean_los_days,
    SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) AS cnt_le_10,
    COUNT(*) AS total_count
  FROM
    base
  WHERE
    category IS NOT NULL
  GROUP BY
    category
)
SELECT
  category,
  ROUND(mean_los_days, 2) AS mean_los_days,
  qs[OFFSET(50)] AS p50_los_days,
  qs[OFFSET(75)] AS p75_los_days,
  qs[OFFSET(90)] AS p90_los_days,
  ROUND(100.0 * cnt_le_10 / total_count, 2) AS pct_rank_10d
FROM
  stats
ORDER BY
  category;