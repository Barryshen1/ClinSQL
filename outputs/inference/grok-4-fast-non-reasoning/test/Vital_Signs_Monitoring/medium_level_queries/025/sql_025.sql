WITH eligible_stays AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    i.stay_id,
    i.intime,
    i.los
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    i.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND i.los >= 1
),
temp_measurements AS (
  SELECT 
    es.stay_id,
    es.intime,
    c.valuenum
  FROM 
    eligible_stays es
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  ON 
    es.subject_id = c.subject_id
    AND es.stay_id = c.stay_id  -- Note: stay_id join assumes hadm_id alignment
  WHERE 
    c.itemid IN (676, 677)
    AND c.valuenum IS NOT NULL 
    AND c.valuenum > 0
    AND c.charttime >= es.intime 
    AND c.charttime < TIMESTAMP_ADD(es.intime, INTERVAL 1 DAY)
),
stay_averages AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS avg_temp_first24
  FROM 
    temp_measurements
  GROUP BY 
    stay_id
  HAVING 
    COUNT(valuenum) > 0
)
SELECT 
  PERCENT_RANK() OVER (ORDER BY avg_temp_first24) * 100 AS percentile_37_5
FROM 
  stay_averages
CROSS JOIN 
  (SELECT 37.5 AS target_temp) t
WHERE 
  avg_temp_first24 <= 37.5
ORDER BY 
  avg_temp_first24
LIMIT 1;