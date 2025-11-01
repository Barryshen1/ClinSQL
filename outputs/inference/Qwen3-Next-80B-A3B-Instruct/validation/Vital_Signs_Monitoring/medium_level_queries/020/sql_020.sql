WITH map_per_stay AS (
  SELECT 
    ie.stay_id,
    AVG(ce.valuenum) AS mean_map
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
    di.label = 'MAP'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND ie.los >= 2  -- at least 48 hours
  GROUP BY 
    ie.stay_id
)
SELECT 
  (SUM(CASE WHEN mean_map <= 85 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS percentile
FROM 
  map_per_stay;