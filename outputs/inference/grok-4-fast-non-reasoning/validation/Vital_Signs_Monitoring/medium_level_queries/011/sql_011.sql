WITH rr_data AS (
  SELECT 
    c.stay_id,
    AVG(c.valuenum) AS avg_rr
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    i.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  ON 
    c.subject_id = i.subject_id 
    AND c.hadm_id = i.hadm_id 
    AND c.stay_id = i.stay_id
  WHERE 
    p.gender = 'M'
    AND (EXTRACT(YEAR FROM i.intime) - p.anchor_age) BETWEEN 54 AND 64
    AND c.itemid = 618
    AND c.valuenum IS NOT NULL 
    AND c.valuenum > 0
    AND c.charttime >= i.intime 
    AND c.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
  GROUP BY 
    c.stay_id
  HAVING 
    COUNT(c.valuenum) >= 1  -- At least one valid RR
),
categorized_rr AS (
  SELECT 
    stay_id,
    avg_rr,
    CASE 
      WHEN avg_rr < 12 THEN '<12'
      WHEN avg_rr >= 12 AND avg_rr <= 20 THEN '12-20'
      WHEN avg_rr >= 21 AND avg_rr <= 29 THEN '21-29'
      WHEN avg_rr >= 30 THEN '>=30'
    END AS rr_category
  FROM 
    rr_data
)
SELECT 
  rr_category,
  COUNT(stay_id) AS n,
  ROUND(AVG(avg_rr), 2) AS mean_rr,
  ROUND(PERCENTILE_CONT(avg_rr, 0.5), 2) AS median_rr,
  ROUND(PERCENTILE_CONT(avg_rr, 0.25), 2) AS q1,
  ROUND(PERCENTILE_CONT(avg_rr, 0.75), 2) AS q3,
  ROUND(PERCENTILE_CONT(avg_rr, 0.75) - PERCENTILE_CONT(avg_rr, 0.25), 2) AS iqr_rr
FROM 
  categorized_rr
GROUP BY 
  rr_category
ORDER BY 
  CASE 
    WHEN rr_category = '<12' THEN 1 
    WHEN rr_category = '12-20' THEN 2 
    WHEN rr_category = '21-29' THEN 3 
    ELSE 4 
  END;