WITH filtered AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'DEATH'
      WHEN discharge_location LIKE '%HOME%' THEN 'HOME'
      WHEN discharge_location LIKE '%FACILITY%' 
           OR discharge_location LIKE '%NURSING%' 
           OR discharge_location LIKE '%SNF%' THEN 'FACILITY'
      ELSE 'OTHER'
    END AS discharge_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.dischtime IS NOT NULL
)
SELECT
  discharge_type,
  COUNT(*) AS total_admissions,
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS los_ge_7_count,
  SAFE_DIVIDE(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END), COUNT(*)) AS proportion_los_ge_7,
  -- Percentile rank of 7 days LOS within that category
  SAFE_DIVIDE(SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END), COUNT(*)) * 100 AS percentile_rank_7day
FROM filtered
WHERE discharge_type IN ('HOME', 'FACILITY', 'DEATH')
GROUP BY discharge_type
ORDER BY discharge_type;