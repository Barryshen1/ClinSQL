WITH max_hr_per_stay AS (
  SELECT 
    i.stay_id,
    MAX(c.valuenum) AS max_heart_rate
  FROM 
    physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p 
    ON i.subject_id = p.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.chartevents c 
    ON i.stay_id = c.stay_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items d 
    ON c.itemid = d.itemid
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
    AND LOWER(d.label) LIKE '%heart rate%'
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 0
    AND c.valuenum < 300
  GROUP BY 
    i.stay_id
)
SELECT 
  APPROX_QUANTILES(max_heart_rate, 3)[OFFSET(3)] - APPROX_QUANTILES(max_heart_rate, 3)[OFFSET(1)] AS interquartile_range
FROM 
  max_hr_per_stay;