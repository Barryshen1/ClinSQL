WITH map_data AS (
  SELECT 
    i.stay_id,
    AVG(ce.valuenum) AS avg_map
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON i.subject_id = ce.subject_id 
    AND i.hadm_id = ce.hadm_id 
    AND i.stay_id = ce.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND ce.charttime >= i.intime 
    AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
    AND di.label LIKE '%Mean Arterial Pressure%' 
    AND ce.valuenum IS NOT NULL 
    AND ce.valuenum > 0
    AND i.los >= 1
  GROUP BY 
    i.stay_id
  HAVING 
    avg_map IS NOT NULL
),
percentile_calc AS (
  SELECT 
    PERCENT_RANK() OVER (ORDER BY avg_map ASC) * 100 AS percentile_75
  FROM 
    map_data
  WHERE 
    75 <= (SELECT MAX(avg_map) FROM map_data)  -- Ensures cohort has data >=75 if needed, but generally for context
)
SELECT 
  ROUND(percentile_75, 2) AS percentile_for_75_mmHg
FROM 
  percentile_calc
  CROSS JOIN (SELECT 75 AS target_map) tm  -- Fixed value for the query
LIMIT 1;