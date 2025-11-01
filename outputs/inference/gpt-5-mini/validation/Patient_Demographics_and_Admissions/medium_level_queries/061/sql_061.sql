WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    -- LOS in days as fractional value
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    -- ensure valid admission/discharge times and non-negative LOS
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 0
),

labeled AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN COALESCE(UPPER(discharge_location), '') LIKE '%HOME%' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_outcome
  FROM cohort
),

agg AS (
  SELECT
    discharge_outcome,
    COUNT(*) AS n_admissions,
    AVG(los_days) AS mean_los,
    -- APPROX_QUANTILES returns an array of size N+1 for N quantiles; with N=100 indices 0..100
    APPROX_QUANTILES(los_days, 100) AS los_qs,
    SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) AS n_le_10
  FROM labeled
  GROUP BY discharge_outcome
)

SELECT
  discharge_outcome,
  n_admissions,
  ROUND(mean_los, 2) AS mean_los_days,
  ROUND(los_qs[OFFSET(50)], 2) AS median_los_days,
  ROUND(los_qs[OFFSET(75)], 2) AS p75_los_days,
  ROUND(los_qs[OFFSET(90)], 2) AS p90_los_days,
  ROUND(100.0 * SAFE_DIVIDE(n_le_10, n_admissions), 2) AS pct_admissions_le_10_days
FROM agg
ORDER BY
  -- order: In-hospital death, Home, Facility (optional)
  CASE discharge_outcome
    WHEN 'In-hospital death' THEN 1
    WHEN 'Home' THEN 2
    WHEN 'Facility' THEN 3
    ELSE 4
  END;