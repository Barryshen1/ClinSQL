WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- pragmatic transfer-in definition: admission_location contains 'transfer'
    AND LOWER(COALESCE(a.admission_location, '')) LIKE '%transfer%'
),
categorized AS (
  SELECT
    hadm_id,
    subject_id,
    anchor_age,
    los_days,
    hospital_expire_flag,
    discharge_location,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in_hospital_mortality'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%home%' THEN 'home'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%snf%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%nursing%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%rehab%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%ltach%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%long term%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%long-term%'
      THEN 'snf_rehab_ltach'
      ELSE NULL
    END AS discharge_group
  FROM cohort
)
SELECT
  discharge_group AS discharge_category,
  COUNT(*) AS n,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  -- APPROX_QUANTILES(...,100) returns 101 quantiles (0..100). Use OFFSET to extract percentiles.
  (APPROX_QUANTILES(los_days, 100))[OFFSET(25)] AS p25_days,
  (APPROX_QUANTILES(los_days, 100))[OFFSET(50)] AS median_days,
  (APPROX_QUANTILES(los_days, 100))[OFFSET(75)] AS p75_days,
  (APPROX_QUANTILES(los_days, 100))[OFFSET(90)] AS p90_days,
  (APPROX_QUANTILES(los_days, 100))[OFFSET(95)] AS p95_days,
  ROUND(100.0 * SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pctile_rank_of_5day_stay_percent
FROM categorized
WHERE discharge_group IS NOT NULL
GROUP BY discharge_group
ORDER BY
  -- order for readability: home, snf/rehab/ltach, in-hospital mortality
  CASE discharge_group
    WHEN 'home' THEN 1
    WHEN 'snf_rehab_ltach' THEN 2
    WHEN 'in_hospital_mortality' THEN 3
    ELSE 4
  END;