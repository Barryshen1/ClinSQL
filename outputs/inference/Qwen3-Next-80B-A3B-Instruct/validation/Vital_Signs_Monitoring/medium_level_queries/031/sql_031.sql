WITH eligible_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.intime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 67 AND 77
),
temperature_measurements AS (
  SELECT 
    e.stay_id,
    c.valuenum
  FROM 
    eligible_patients e
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON e.stay_id = c.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  WHERE 
    LOWER(d.label) LIKE '%temperature%'
    AND c.charttime >= e.intime
    AND c.charttime < DATE_ADD(e.intime, INTERVAL 24 HOUR)
    AND c.valuenum IS NOT NULL
    AND c.valuenum BETWEEN 30 AND 42  -- plausible range for body temperature in Celsius
),
per_stay_avg_temp AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS avg_temp
  FROM 
    temperature_measurements
  GROUP BY 
    stay_id
)
SELECT 
  100.0 * SUM(CASE WHEN avg_temp <= 36.0 THEN 1 ELSE 0 END) / COUNT(*) AS percentile
FROM 
  per_stay_avg_temp;