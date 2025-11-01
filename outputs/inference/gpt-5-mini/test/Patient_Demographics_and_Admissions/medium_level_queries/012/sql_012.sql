WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    LOWER(COALESCE(a.discharge_location, '')) AS discharge_location_lower,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) >= 0
)

SELECT
  discharge_category,
  COUNT(*) AS admissions,
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS admissions_los_ge_7,
  ROUND(100.0 * SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_los_ge_7,
  SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) AS admissions_los_le_7,
  ROUND(100.0 * SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percentile_rank_of_7day
FROM (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location_lower LIKE '%home%' THEN 'home'
      WHEN (
        discharge_location_lower LIKE '%snf%' OR
        discharge_location_lower LIKE '%nurs%' OR
        discharge_location_lower LIKE '%facility%' OR
        discharge_location_lower LIKE '%rehab%' OR
        discharge_location_lower LIKE '%long%' OR
        discharge_location_lower LIKE '%ltach%' OR
        discharge_location_lower LIKE '%skilled%'
      ) THEN 'facility'
      ELSE 'other'
    END AS discharge_category
  FROM cohort
)
WHERE discharge_category IN ('home', 'facility', 'in-hospital death')
GROUP BY discharge_category
ORDER BY
  CASE discharge_category
    WHEN 'home' THEN 1
    WHEN 'facility' THEN 2
    WHEN 'in-hospital death' THEN 3
    ELSE 4
  END;