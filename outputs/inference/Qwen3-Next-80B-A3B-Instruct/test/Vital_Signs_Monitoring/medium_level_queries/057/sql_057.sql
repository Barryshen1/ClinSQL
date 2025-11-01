WITH temp_averages AS (
  SELECT 
    i.stay_id,
    AVG(ce.valuenum) AS avg_temperature
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON i.stay_id = ce.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 85 AND 95
    AND LOWER(di.label) LIKE '%temperature%'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 30 AND 42
  GROUP BY 
    i.stay_id
)
SELECT 
  SUM(CASE WHEN avg_temperature <= 36.0 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS percentile_rank
FROM 
  temp_averages;