WITH temp_stays AS (
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
    AND p.anchor_age BETWEEN 67 AND 77
    AND ce.itemid = 223762  -- Temperature in Celsius
    AND ce.charttime BETWEEN ie.intime AND TIMESTAMP_ADD(ie.intime, INTERVAL 24 HOUR)
  GROUP BY 
    ie.stay_id
)
SELECT 
  PERCENT_RANK() OVER (ORDER BY avg_temp) AS percentile_rank
FROM 
  temp_stays
WHERE 
  avg_temp = 36.0;