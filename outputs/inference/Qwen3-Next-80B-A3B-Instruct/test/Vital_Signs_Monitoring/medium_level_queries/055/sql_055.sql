WITH spo2_first_24h AS (
  SELECT 
    i.stay_id,
    AVG(ce.valuenum) AS avg_spo2_first_24h
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
    p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
    AND di.label = 'SpO2'
    AND ce.charttime >= i.intime
    AND ce.charttime < i.intime + INTERVAL 24 HOUR
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100
  GROUP BY 
    i.stay_id
)
SELECT 
  (SUM(CASE WHEN avg_spo2_first_24h <= 88 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS percentile_88
FROM 
  spo2_first_24h;