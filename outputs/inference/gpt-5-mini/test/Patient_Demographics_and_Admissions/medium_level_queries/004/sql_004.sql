WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- fractional hospital LOS in days
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND), 86400.0) AS los_days,
    a.hospital_expire_flag,
    a.discharge_location,
    -- derive discharge category (death takes precedence)
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN LOWER(a.discharge_location) LIKE '%hospice%' THEN 'hospice'
      WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 'home'
      ELSE NULL
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND UPPER(a.admission_type) != 'EMERGENCY'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
)
SELECT
  discharge_category,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  -- APPROX_QUANTILES(..., 100) returns array indices 0..100 representing percentiles
  ROUND( (APPROX_QUANTILES(los_days, 100))[OFFSET(50)], 2) AS median_p50_days,
  ROUND( (APPROX_QUANTILES(los_days, 100))[OFFSET(75)], 2) AS p75_days,
  ROUND( (APPROX_QUANTILES(los_days, 100))[OFFSET(90)], 2) AS p90_days,
  ROUND(100.0 * SUM(CASE WHEN los_days < 5 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_los_lt_5
FROM
  cohort
WHERE
  discharge_category IS NOT NULL
GROUP BY
  discharge_category
ORDER BY
  discharge_category;