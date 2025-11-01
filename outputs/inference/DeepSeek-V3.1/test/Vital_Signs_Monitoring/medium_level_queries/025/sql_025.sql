WITH temp_avg_per_stay AS (
  SELECT 
    ie.stay_id,
    AVG(ce.valuenum) AS avg_temp
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND ce.itemid = 223762  -- Temperature Celsius
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= ie.intime
    AND ce.charttime < DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
  GROUP BY ie.stay_id
)
SELECT 
  PERCENT_RANK() OVER (ORDER BY avg_temp) * 100 AS percentile_rank
FROM temp_avg_per_stay
WHERE avg_temp = 37.5;