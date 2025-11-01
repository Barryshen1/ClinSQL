WITH systolic_bp AS (
  SELECT 
    ie.stay_id,
    AVG(ce.valuenum) AS avg_sys_bp
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON ie.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ie.stay_id = ce.stay_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND ce.itemid = 220050  
    AND ce.charttime BETWEEN ie.intime AND TIMESTAMP_ADD(ie.intime, INTERVAL 48 HOUR)
  GROUP BY 
    ie.stay_id
)
SELECT 
  COUNTIF(avg_sys_bp <= 150) / COUNT(*) AS percentile
FROM 
  systolic_bp;