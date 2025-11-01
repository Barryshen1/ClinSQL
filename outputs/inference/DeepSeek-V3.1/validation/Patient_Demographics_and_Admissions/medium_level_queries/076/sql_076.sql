WITH cohort AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.dischtime IS NOT NULL  -- Exclude ongoing admissions
)
SELECT
  hospital_expire_flag,
  COUNT(*) AS n_patients,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
  NULL AS percentile_5_day_los
FROM cohort
GROUP BY hospital_expire_flag

UNION ALL

SELECT
  NULL AS hospital_expire_flag,
  NULL AS n_patients,
  NULL AS mean_los,
  NULL AS median_los,
  NULL AS p75_los,
  NULL AS p90_los,
  SAFE_DIVIDE(COUNTIF(los_days <= 5) - 1, COUNT(*) - 1) * 100 AS percentile_5_day_los
FROM cohort;