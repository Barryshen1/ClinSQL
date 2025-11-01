WITH mean_hr AS (
  SELECT 
    ie.stay_id,
    AVG(ce.valuenum) AS mean_hr
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ie.stay_id = ce.stay_id
  WHERE 
    ce.itemid = 220050  
  GROUP BY 
    ie.stay_id
),
patient_info AS (
  SELECT 
    ie.stay_id,
    p.gender,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON ie.subject_id = p.subject_id
)
SELECT 
  APPROX_QUANTILES(m.mean_hr, 100)[OFFSET(50)] AS median_mean_hr
FROM 
  mean_hr m
INNER JOIN 
  patient_info p ON m.stay_id = p.stay_id
WHERE 
  p.gender = 'M' 
  AND p.anchor_age BETWEEN 40 AND 50;