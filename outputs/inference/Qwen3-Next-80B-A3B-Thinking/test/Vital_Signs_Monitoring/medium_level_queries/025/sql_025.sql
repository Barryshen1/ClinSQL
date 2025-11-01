WITH icu_patients AS (
  SELECT 
    i.stay_id,
    i.intime,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
),
temp_readings AS (
  SELECT 
    c.stay_id,
    c.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN icu_patients ip ON c.stay_id = ip.stay_id
  WHERE c.itemid = 223761
    AND c.charttime BETWEEN ip.intime AND ip.intime + INTERVAL 24 HOUR
),
avg_temps AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS avg_temp
  FROM temp_readings
  GROUP BY stay_id
)
SELECT 
  SUM(CASE WHEN avg_temp <= 37.5 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percentile
FROM avg_temps;