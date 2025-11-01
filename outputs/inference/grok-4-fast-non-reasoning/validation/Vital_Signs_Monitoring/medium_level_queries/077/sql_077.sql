WITH heart_rates AS (
  SELECT 
    c.stay_id,
    AVG(c.valuenum) AS avg_hr,
    COUNT(c.valuenum) AS num_measurements,
    PERCENT_RANK() OVER (ORDER BY AVG(c.valuenum)) * 100 AS percentile
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.subject_id = i.subject_id AND c.stay_id = i.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE 
    c.itemid = 220045  -- Heart Rate
    AND c.valuenum IS NOT NULL 
    AND c.valuenum > 0
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 42 AND 52
    AND i.intime <= c.charttime AND c.charttime <= i.outtime
  GROUP BY 
    c.stay_id
  HAVING 
    COUNT(c.valuenum) > 0  -- Ensure valid measurements per stay
),
cohort_stats AS (
  SELECT 
    COUNT(*) AS cohort_size
  FROM 
    heart_rates
)
SELECT 
  cs.cohort_size,
  ROUND(hr.percentile, 2) AS percentile
FROM 
  heart_rates hr
CROSS JOIN 
  cohort_stats cs
WHERE 
  ROUND(hr.avg_hr, 2) = 90;  -- Target average for the 47-year-old female patient;