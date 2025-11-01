WITH admissions_males_81_91 AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    LOWER(COALESCE(a.admission_location, '')) AS admission_location,
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND), 86400.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) > 0
    -- pragmatic text filter to capture "transfer from hospital" variants
    AND LOWER(COALESCE(a.admission_location, '')) LIKE '%transfer%'
    AND LOWER(COALESCE(a.admission_location, '')) LIKE '%hosp%'
),
stratified AS (
  SELECT
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%hospice%' THEN 'hospice'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%home%' THEN 'home'
      ELSE NULL
    END AS discharge_group,
    los_days
  FROM admissions_males_81_91
)
SELECT
  discharge_group,
  COUNT(*) AS n,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(25)], 2) AS p25_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS p50_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS p75_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(90)], 2) AS p90_los_days,
  ROUND(100.0 * SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_le_10_days
FROM stratified
WHERE discharge_group IS NOT NULL
GROUP BY discharge_group
ORDER BY discharge_group;