WITH eligible_stays AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    i.intime,
    p.gender,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    i.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 56 AND 66
),
map_data AS (
  SELECT 
    es.stay_id,
    c.charttime,
    c.valuenum AS map_value
  FROM 
    eligible_stays es
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  ON 
    es.subject_id = c.subject_id
    AND es.stay_id = c.stay_id
  WHERE 
    c.itemid = 220052  -- MAP
    AND c.valuenum IS NOT NULL 
    AND c.valuenum > 0
    AND c.charttime >= es.intime
    AND c.charttime <= TIMESTAMP_ADD(es.intime, INTERVAL 48 HOUR)
),
per_stay_means AS (
  SELECT 
    stay_id,
    AVG(map_value) AS mean_map
  FROM 
    map_data
  GROUP BY 
    stay_id
  HAVING 
    COUNT(*) >= 1  -- Ensure data in first 48h
),
categorized_stays AS (
  SELECT 
    CASE 
      WHEN mean_map < 65 THEN '<65'
      WHEN mean_map >= 65 AND mean_map <= 74 THEN '65-74'
      WHEN mean_map >= 75 AND mean_map <= 84 THEN '75-84'
      ELSE '>=85'
    END AS map_category,
    mean_map,
    -- Pre-compute percentiles per category
    AVG(mean_map) OVER (PARTITION BY 
      CASE 
        WHEN mean_map < 65 THEN '<65'
        WHEN mean_map >= 65 AND mean_map <= 74 THEN '65-74'
        WHEN mean_map >= 75 AND mean_map <= 84 THEN '75-84'
        ELSE '>=85'
      END
    ) AS category_mean_map,
    PERCENTILE_CONT(mean_map, 0.5) OVER (PARTITION BY 
      CASE 
        WHEN mean_map < 65 THEN '<65'
        WHEN mean_map >= 65 AND mean_map <= 74 THEN '65-74'
        WHEN mean_map >= 75 AND mean_map <= 84 THEN '75-84'
        ELSE '>=85'
      END
    ) AS category_median_map,
    PERCENTILE_CONT(mean_map, 0.25) OVER (PARTITION BY 
      CASE 
        WHEN mean_map < 65 THEN '<65'
        WHEN mean_map >= 65 AND mean_map <= 74 THEN '65-74'
        WHEN mean_map >= 75 AND mean_map <= 84 THEN '75-84'
        ELSE '>=85'
      END
    ) AS category_iqr_lower,
    PERCENTILE_CONT(mean_map, 0.75) OVER (PARTITION BY 
      CASE 
        WHEN mean_map < 65 THEN '<65'
        WHEN mean_map >= 65 AND mean_map <= 74 THEN '65-74'
        WHEN mean_map >= 75 AND mean_map <= 84 THEN '75-84'
        ELSE '>=85'
      END
    ) AS category_iqr_upper
  FROM 
    per_stay_means
)
SELECT 
  map_category,
  COUNT(*) AS stay_count,
  MAX(category_mean_map) AS mean_map,  -- Same value for all rows in category
  MAX(category_median_map) AS median_map,
  MAX(category_iqr_lower) AS iqr_lower,
  MAX(category_iqr_upper) AS iqr_upper
FROM 
  categorized_stays
GROUP BY 
  map_category
ORDER BY 
  CASE map_category
    WHEN '<65' THEN 1
    WHEN '65-74' THEN 2
    WHEN '75-84' THEN 3
    WHEN '>=85' THEN 4
  END;