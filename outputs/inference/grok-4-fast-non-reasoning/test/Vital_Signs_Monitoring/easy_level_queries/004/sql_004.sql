WITH temp_stays AS (
  SELECT 
    c.stay_id,
    AVG(c.valuenum) AS mean_temp
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.subject_id = i.subject_id 
    AND c.stay_id = i.stay_id
    AND c.charttime BETWEEN i.intime AND i.outtime
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND c.itemid IN (676, 677, 678, 679)
    AND c.valuenum IS NOT NULL
    AND c.valuenum BETWEEN 20 AND 45
  GROUP BY 
    c.stay_id
)
SELECT 
  PERCENTILE_CONT(mean_temp, 0.75) AS p75_mean_temp
FROM 
  temp_stays;