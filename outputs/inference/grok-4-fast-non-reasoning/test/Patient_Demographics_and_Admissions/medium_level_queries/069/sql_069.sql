WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age,
    p.gender,
    a.admission_type
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.admission_type = 'EMERGENCY'
    AND a.hospital_expire_flag = 0 
    AND a.dischtime > a.admittime  -- Exclude day-0 deaths
)

-- Proportions by outcome
SELECT 
  hospital_expire_flag,
  COUNT(*) AS total_count,
  COUNTIF(los_days >= 7) AS los_ge7_count,
  COUNTIF(los_days >= 7) * 1.0 / COUNT(*) AS proportion_los_ge7
FROM 
  cohort
GROUP BY 
  hospital_expire_flag

UNION ALL

-- Percentile rank of 7-day LOS (overall cohort)
SELECT 
  NULL AS hospital_expire_flag,
  NULL AS total_count,
  NULL AS los_ge7_count,
  PERCENT_RANK() OVER (ORDER BY los_days) AS percentile_rank_7days
FROM 
  cohort
WHERE 
  los_days = 7  -- Rank exactly at 7 days
;