WITH map_avgs AS (
  SELECT 
    ic.stay_id,
    AVG(ce.valuenum) AS avg_map
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ic.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON ce.stay_id = ic.stay_id 
    AND ce.itemid = 220052
    AND ce.valuenum IS NOT NULL
  WHERE 
    p.gender = 'M'
    AND EXTRACT(YEAR FROM ic.intime) - p.anchor_year + p.anchor_age BETWEEN 38 AND 48
  GROUP BY 
    ic.stay_id
)
SELECT 
  COUNTIF(avg_map <= 60) / COUNT(*) AS proportion_le_60
FROM 
  map_avgs;