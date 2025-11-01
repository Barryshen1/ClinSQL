WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- LOS in fractional days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    LOWER(COALESCE(a.discharge_location, '')) AS discharge_location,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
    -- Exclude admissions that have any ICU stay (so we focus on general-ward admissions)
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.hadm_id = a.hadm_id
    )
)

SELECT
  discharge_dest,
  COUNT(*) AS n_admissions,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS p50_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS p75_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(90)], 2) AS p90_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(95)], 2) AS p95_days,
  -- Percentile rank of a 7-day stay: percent of admissions with LOS <= 7 days
  ROUND(100.0 * SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_rank_7day
FROM (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'death'
      WHEN discharge_location LIKE '%hospice%' THEN 'hospice'
      WHEN discharge_location LIKE '%home%' THEN 'home'
      ELSE 'other'
    END AS discharge_dest
  FROM cohort
)
WHERE discharge_dest IN ('home', 'hospice', 'death')
GROUP BY discharge_dest
ORDER BY discharge_dest;