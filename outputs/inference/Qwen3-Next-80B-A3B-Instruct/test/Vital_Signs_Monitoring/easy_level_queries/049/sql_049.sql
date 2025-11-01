WITH map_first_24h AS (
  SELECT 
    ie.stay_id,
    AVG(ce.valuenum) AS mean_map_24h
  FROM 
    physionet-data.mimiciv_3_1_icu.chartevents ce
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.icustays ie 
    ON ce.stay_id = ie.stay_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p 
    ON ie.subject_id = p.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items di 
    ON ce.itemid = di.itemid
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 85 AND 95
    AND di.label IN ('Mean Arterial Pressure', 'MAP')
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 20 AND 200  -- physiologically plausible range
    AND ce.charttime >= ie.intime
    AND ce.charttime < ie.intime + INTERVAL 24 HOUR
  GROUP BY 
    ie.stay_id
)
SELECT 
  STDDEV(mean_map_24h) AS std_dev_first_24h_mean_map
FROM 
  map_first_24h;