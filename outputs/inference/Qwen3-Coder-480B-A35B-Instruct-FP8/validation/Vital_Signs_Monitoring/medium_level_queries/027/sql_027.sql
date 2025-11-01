WITH cohort AS (
  SELECT 
    i.stay_id,
    p.subject_id,
    p.anchor_age,
    p.gender
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.icustays i
    ON p.subject_id = i.subject_id
  WHERE 
    p.gender = 'F' AND
    p.anchor_age BETWEEN 80 AND 90
),
hr_measurements AS (
  SELECT 
    c.stay_id,
    AVG(ce.valuenum) AS avg_hr
  FROM 
    cohort c
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.chartevents ce
    ON c.stay_id = ce.stay_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE 
    di.label = 'Heart Rate' AND
    ce.valuenum IS NOT NULL AND
    ce.valuenum BETWEEN 0 AND 300
  GROUP BY 
    c.stay_id
),
percentile_data AS (
  SELECT 
    avg_hr,
    PERCENT_RANK() OVER (ORDER BY avg_hr) * 100 AS percentile_rank
  FROM 
    hr_measurements
)
SELECT 
  MAX(CASE WHEN avg_hr <= 110 THEN percentile_rank ELSE NULL END) AS percentile_of_110_bpm
FROM 
  percentile_data;