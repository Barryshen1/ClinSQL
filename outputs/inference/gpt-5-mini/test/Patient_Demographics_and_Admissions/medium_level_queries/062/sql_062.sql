WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.discharge_location,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

categorized AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in_hospital_death'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%home%' THEN 'home'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%snf%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%rehab%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%ltach%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%nursing%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%long%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%skilled%'
        THEN 'snf_rehab_ltach'
      ELSE 'other'
    END AS discharge_group
  FROM cohort
)

SELECT
  discharge_group,
  COUNT(*) AS n_admissions,
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS n_los_ge_7,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END), COUNT(*)), 2) AS pct_los_ge_7,
  SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) AS n_los_ge_14,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END), COUNT(*)), 2) AS pct_los_ge_14,
  -- approximate 14th percentile of LOS (in days)
  APPROX_QUANTILES(los_days, 100)[OFFSET(14)] AS los_p14_days_approx
FROM categorized
WHERE discharge_group IN ('home', 'snf_rehab_ltach', 'in_hospital_death')
GROUP BY discharge_group
ORDER BY discharge_group;