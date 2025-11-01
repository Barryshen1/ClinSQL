WITH first_24h_map AS (
  SELECT 
    i.stay_id,
    AVG(ce.valuenum) AS mean_map_24h
  FROM 
    physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.chartevents ce
    ON i.stay_id = ce.stay_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND di.label IN ('Mean Arterial Pressure', 'MAP')
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= i.intime
    AND ce.charttime < i.intime + INTERVAL 24 HOUR
  GROUP BY 
    i.stay_id
),
percentile_calc AS (
  SELECT 
    100.0 * SUM(CASE WHEN mean_map_24h <= 75 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_75
  FROM 
    first_24h_map
)
SELECT 
  percentile_75
FROM 
  percentile_calc;