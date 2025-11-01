WITH per_stay_avg AS (
  SELECT 
      ie.stay_id,
      AVG(ce.valuenum) AS mean_heart_rate
  FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON ie.subject_id = p.subject_id
  INNER JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce 
      ON ie.stay_id = ce.stay_id
  WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 40 AND 50
      AND ce.itemid = 220045  -- Heart Rate itemid
      AND ce.valuenum IS NOT NULL  -- Ensure numeric values
  GROUP BY 
      ie.stay_id
)
SELECT 
    APPROX_QUANTILES(mean_heart_rate, 100)[OFFSET(50)] AS median_heart_rate
FROM 
    per_stay_avg;