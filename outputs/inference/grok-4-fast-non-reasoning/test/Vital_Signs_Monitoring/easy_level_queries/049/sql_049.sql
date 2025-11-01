WITH first_stays AS (
  SELECT 
    i.subject_id,
    i.stay_id,
    i.hadm_id,
    p.gender,
    p.anchor_age,
    i.intime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    i.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 85 AND 95
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) = 1
),
map_data AS (
  SELECT 
    fs.stay_id,
    ce.charttime,
    ce.valuenum
  FROM 
    first_stays fs
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON 
    fs.subject_id = ce.subject_id 
    AND fs.hadm_id = ce.hadm_id 
    AND fs.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (220052, 220277)  -- MAP itemids
    AND ce.valuenum IS NOT NULL 
    AND ce.valuenum > 0
    AND ce.charttime >= fs.intime 
    AND ce.charttime < fs.intime + INTERVAL 1 DAY
)
SELECT 
  STDDEV(avg_map) AS first_24h_map_stddev
FROM (
  SELECT 
    stay_id,
    AVG(valuenum) AS avg_map
  FROM 
    map_data
  GROUP BY 
    stay_id
);