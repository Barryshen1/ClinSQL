WITH filtered_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
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
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_type = 'TRANSFER'
    AND a.dischtime IS NOT NULL
),
categorized_outcomes AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'DEATH'
      WHEN discharge_location = 'HOME' THEN 'HOME'
      WHEN discharge_location IN ('SNF', 'REHAB', 'LTAC') THEN 'FACILITY'
      ELSE NULL 
    END AS outcome_category,
    PERCENT_RANK() OVER (PARTITION BY 
      CASE 
        WHEN hospital_expire_flag = 1 THEN 'DEATH'
        WHEN discharge_location = 'HOME' THEN 'HOME'
        WHEN discharge_location IN ('SNF', 'REHAB', 'LTAC') THEN 'FACILITY'
        ELSE NULL 
      END 
      ORDER BY DATE_DIFF(a.dischtime, a.admittime, DAY)
    ) AS los_percent_rank
  FROM 
    filtered_admissions a
  WHERE 
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'DEATH'
      WHEN discharge_location = 'HOME' THEN 'HOME'
      WHEN discharge_location IN ('SNF', 'REHAB', 'LTAC') THEN 'FACILITY'
      ELSE NULL 
    END IS NOT NULL
)
SELECT 
  outcome_category,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(STDDEV(los_days), 2) AS sd_los,
  ROUND(AVG(CASE WHEN los_days <= 5 THEN los_percent_rank ELSE NULL END) * 100, 2) AS percentile_rank_5day_los
FROM 
  categorized_outcomes
GROUP BY 
  outcome_category
ORDER BY 
  outcome_category;