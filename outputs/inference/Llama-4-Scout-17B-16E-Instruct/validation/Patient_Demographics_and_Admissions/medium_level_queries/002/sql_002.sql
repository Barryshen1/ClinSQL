WITH 
  -- Filter and calculate LOS for relevant admissions
  relevant_admissions AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.deathtime,
      p.anchor_age,
      p.gender,
      s.curr_service,
      t.eventtype AS discharge_disposition
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    LEFT JOIN 
      `physionet-data.mimiciv_3_1_hosp.services` s 
        ON a.hadm_id = s.hadm_id AND s.transfertime = (SELECT MAX(transfertime) FROM `physionet-data.mimiciv_3_1_hosp.services` s2 WHERE s2.hadm_id = a.hadm_id)
    LEFT JOIN 
      `physionet-data.mimiciv_3_1_hosp.transfers` t 
        ON a.hadm_id = t.hadm_id AND t.eventtype IN ('discharge', 'death')
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 59 AND 69
      AND s.curr_service = 'medicine'
  ),
  
  -- Calculate LOS and categorize discharge disposition
  los_data AS (
    SELECT 
      hadm_id,
      TIMESTAMPDIFF(DAY, admittime, COALESCE(dischtime, deathtime)) AS los,
      CASE 
        WHEN discharge_disposition = 'discharge' THEN 'home/facility'
        WHEN discharge_disposition = 'death' THEN 'in-hospital death'
        ELSE 'unknown'
      END AS discharge_category
    FROM 
      relevant_admissions
  )

-- Calculate LOS distribution and percent ≤ 10 days
SELECT 
  discharge_category,
  AVG(los) AS mean_los,
  PERCENTILE_CONT(0.25, los) AS p25_los,
  PERCENTILE_CONT(0.5, los) AS median_los,
  PERCENTILE_CONT(0.75, los) AS p75_los,
  PERCENTILE_CONT(0.9, los) AS p90_los,
  SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS percent_los_leq_10_days
FROM 
  los_data
GROUP BY 
  discharge_category;