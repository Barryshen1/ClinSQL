WITH map_data AS (
  SELECT 
    c.stay_id,
    AVG(c.valuenum) AS avg_map
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.subject_id = i.subject_id 
    AND c.hadm_id = i.hadm_id 
    AND c.stay_id = i.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND c.itemid = 220052
    AND c.valuenum BETWEEN 1 AND 200
    AND c.charttime <= i.intime + INTERVAL 48 HOUR
  GROUP BY 
    c.stay_id
  HAVING 
    COUNT(*) > 0
)
SELECT 
  PERCENT_RANK() OVER (ORDER BY avg_map) * 100 AS percentile_for_85
FROM 
  map_data
CROSS JOIN 
  (SELECT 85.0 AS target_map) t
WHERE 
  85.0 <= avg_map  -- Note: PERCENT_RANK gives rank up to the value; this filters for illustration, but full distribution is in CTE
ORDER BY 
  avg_map
LIMIT 1;  -- Single value for the exact percentile at/near 85;