WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.dischtime IS NOT NULL
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) >= 0
),
outcomes AS (
  SELECT 
    *,
    CASE 
      WHEN deathtime IS NOT NULL THEN 'Death'
      WHEN discharge_location LIKE '%HOME%' THEN 'Home'
      WHEN discharge_location LIKE '%SNF%' 
        OR discharge_location LIKE '%REHAB%' 
        OR discharge_location LIKE '%LTAC%' 
        OR discharge_location LIKE '%ACUTE%' 
        OR discharge_location LIKE '%FACILIT%' THEN 'Facility'
      ELSE NULL 
    END AS discharge_outcome
  FROM cohort
)
SELECT 
  discharge_outcome,
  PERCENTILE_CONT(0.5) IGNORE NULLS WITHIN GROUP (ORDER BY los_days) AS median_los_days,
  PERCENTILE_CONT(0.25) IGNORE NULLS WITHIN GROUP (ORDER BY los_days) AS q1_los_days,
  PERCENTILE_CONT(0.75) IGNORE NULLS WITHIN GROUP (ORDER BY los_days) AS q3_los_days,
  MAX(PERCENT_RANK() OVER (PARTITION BY discharge_outcome ORDER BY los_days)) AS percentile_rank_14day
FROM outcomes
WHERE discharge_outcome IS NOT NULL
  AND los_days = 14
GROUP BY discharge_outcome
ORDER BY 
  CASE discharge_outcome 
    WHEN 'Home' THEN 1 
    WHEN 'Facility' THEN 2 
    WHEN 'Death' THEN 3 
  END;