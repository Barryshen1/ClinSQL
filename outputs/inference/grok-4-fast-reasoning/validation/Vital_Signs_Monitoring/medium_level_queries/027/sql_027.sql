WITH stay_avgs AS (
  SELECT 
    c.stay_id,
    AVG(c.valuenum) AS avg_hr
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON c.subject_id = p.subject_id
  WHERE 
    c.itemid = 220045
    AND c.valuenum IS NOT NULL
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
  GROUP BY 
    c.stay_id
)
SELECT 
  COUNT(*) AS total_stays,
  COUNTIF(avg_hr <= 110) AS num_stays_leq_110,
  (COUNTIF(avg_hr <= 110) * 100.0 / COUNT(*)) AS percentile
FROM 
  stay_avgs;