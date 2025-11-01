WITH male_64_74 AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
),

admission_data AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    INT64(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN a.discharge_location LIKE '%HOME%' THEN 'Home'
      WHEN a.discharge_location LIKE '%SNF%' OR
           a.discharge_location LIKE '%REHAB%' OR
           a.discharge_location LIKE '%LTACH%' THEN 'SNF/Rehab/LTACH'
      ELSE 'Other'
    END AS discharge_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN male_64_74 m ON a.subject_id = m.subject_id
  WHERE a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

percentiles AS (
  SELECT
    discharge_group,
    ROUND(PERCENTILE_CONT(los_days, 0.14) OVER (PARTITION BY discharge_group), 2) AS p14_los_days
  FROM admission_data
  GROUP BY discharge_group, los_days
)

SELECT
  a.discharge_group,
  COUNT(*) AS total_patients,
  SUM(CASE WHEN a.los_days >= 7 THEN 1 ELSE 0 END) AS los_ge7_count,
  ROUND(SUM(CASE WHEN a.los_days >= 7 THEN 1 ELSE 0 END) / COUNT(*), 4) AS proportion_los_ge7,
  p.p14_los_days
FROM admission_data a
JOIN percentiles p ON a.discharge_group = p.discharge_group
GROUP BY a.discharge_group, p.p14_los_days
ORDER BY a.discharge_group;