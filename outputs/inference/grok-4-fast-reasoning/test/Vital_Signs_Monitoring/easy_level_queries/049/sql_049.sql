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
    p.gender = 'M' 
    AND p.anchor_age >= 85
),
map_values AS (
  SELECT 
    es.stay_id, 
    ce.charttime, 
    ce.valuenum
  FROM 
    eligible_stays es
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON 
    es.stay_id = ce.stay_id
  WHERE 
    ce.itemid = 220052
    AND ce.charttime >= es.intime
    AND ce.charttime < TIMESTAMP_ADD(es.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
),
stay_means AS (
  SELECT 
    stay_id, 
    AVG(valuenum) AS mean_map
  FROM 
    map_values
  GROUP BY 
    stay_id
)
SELECT 
  STDDEV(mean_map) AS stddev_first24h_map
FROM 
  stay_means;