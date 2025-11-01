WITH avg_map AS (
  SELECT 
    ie.stay_id,
    AVG(ce.valuenum) AS avg_map
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON ie.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ie.stay_id = ce.stay_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
    AND ce.itemid = 50821  
  GROUP BY 
    ie.stay_id
)
SELECT 
  SAFE_DIVIDE(
    COUNT(CASE WHEN avg_map.avg_map <= 60 THEN 1 END), 
    COUNT(*)
  ) AS proportion
FROM 
  avg_map;