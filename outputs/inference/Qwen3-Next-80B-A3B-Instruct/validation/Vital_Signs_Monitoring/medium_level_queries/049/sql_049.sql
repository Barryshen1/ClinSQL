WITH sbp_48h AS (
  SELECT 
    i.stay_id,
    AVG(ce.valuenum) AS avg_sbp
  FROM 
    physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.chartevents ce
    ON i.stay_id = ce.stay_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND LOWER(di.label) LIKE '%systolic%'  -- Capture various label formats
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= i.intime
    AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
  GROUP BY 
    i.stay_id
  HAVING 
    AVG(ce.valuenum) IS NOT NULL
)
SELECT 
  (COUNT(CASE WHEN avg_sbp <= 130 THEN 1 END) * 100.0 / COUNT(*)) AS percentile
FROM 
  sbp_48h;