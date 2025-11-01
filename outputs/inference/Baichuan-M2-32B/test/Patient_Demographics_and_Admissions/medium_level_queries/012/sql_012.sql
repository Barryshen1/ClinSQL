WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    -- Compute LOS in days
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.dischtime IS NOT NULL
)
SELECT
  discharge_group,
  COUNT(*) AS total_count,
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS los_ge7_count,
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS proportion_ge7,
  SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) AS los_le7_count,
  SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS percentile_rank_7d
FROM (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location = 'HOME' THEN 'discharged home'
      ELSE 'discharged to facility'
    END AS discharge_group
  FROM cohort
)
GROUP BY discharge_group
ORDER BY discharge_group;