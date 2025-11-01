WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND LOWER(COALESCE(a.admission_location, '')) LIKE '%transfer%'
),
classified AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%home%' THEN 'Discharged home'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%nurs%' THEN 'Facility'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%snf%' THEN 'Facility'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%skilled%' THEN 'Facility'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%rehab%' THEN 'Facility'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%long%' THEN 'Facility'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%ltc%' THEN 'Facility'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%care%' THEN 'Facility'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%facility%' THEN 'Facility'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%nursing%' THEN 'Facility'
      ELSE 'Other'
    END AS discharge_group
  FROM cohort
)
SELECT
  discharge_group,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV_SAMP(los_days), 2) AS sd_los_days,
  ROUND(100.0 * SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_le_5day
FROM classified
WHERE discharge_group IN ('Discharged home', 'Facility', 'In-hospital death')
GROUP BY discharge_group
ORDER BY
  CASE
    WHEN discharge_group = 'Discharged home' THEN 1
    WHEN discharge_group = 'Facility' THEN 2
    WHEN discharge_group = 'In-hospital death' THEN 3
    ELSE 4
  END;