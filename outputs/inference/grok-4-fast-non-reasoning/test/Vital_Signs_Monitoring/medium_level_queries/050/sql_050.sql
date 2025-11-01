WITH eligible_stays AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    i.stay_id,
    i.hadm_id,
    i.intime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    i.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND i.first_careunit LIKE '%ICU%'
),
hr_data AS (
  SELECT 
    es.stay_id,
    c.charttime,
    c.valuenum AS hr
  FROM 
    eligible_stays es
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  ON 
    es.subject_id = c.subject_id
    AND es.hadm_id = c.hadm_id
    AND es.stay_id = c.stay_id
  WHERE 
    c.itemid = 220045
    AND c.valuenum > 0
    AND c.valuenum <= 300
    AND c.charttime >= es.intime
    AND c.charttime < TIMESTAMP_ADD(es.intime, INTERVAL 24 HOUR)
),
stay_avg_hr AS (
  SELECT 
    stay_id,
    AVG(hr) AS avg_hr
  FROM 
    hr_data
  GROUP BY 
    stay_id
  HAVING 
    AVG(hr) IS NOT NULL
)
SELECT 
  PERCENT_RANK() OVER (ORDER BY avg_hr) * 100 AS percentile_for_110
FROM 
  stay_avg_hr
WHERE 
  110 <= avg_hr
ORDER BY 
  avg_hr
LIMIT 1;