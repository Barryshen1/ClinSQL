WITH temp_measurements AS (
  SELECT 
    ie.stay_id,
    AVG(ce.valuenum) AS avg_temp
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ie.stay_id = ce.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON ie.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND ce.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label LIKE '%Temperature%')
    AND ce.charttime BETWEEN ie.intime AND TIMESTAMP_ADD(ie.intime, INTERVAL 24 HOUR)
  GROUP BY 
    ie.stay_id
),
percentile_calc AS (
  SELECT 
    avg_temp,
    PERCENT_RANK() OVER (ORDER BY avg_temp) AS percentile_rank
  FROM 
    temp_measurements
)
SELECT 
  percentile_rank
FROM 
  percentile_calc
WHERE 
  avg_temp <= 37.5
ORDER BY 
  percentile_rank DESC
LIMIT 1;