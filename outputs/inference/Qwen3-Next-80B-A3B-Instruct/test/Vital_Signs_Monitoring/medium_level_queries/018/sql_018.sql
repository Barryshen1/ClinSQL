WITH systolic_bp_first_48 AS (
  SELECT 
    i.stay_id,
    AVG(ce.valuenum) AS mean_systolic_bp
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
    AND p.anchor_age BETWEEN 75 AND 85
    AND LOWER(di.label) LIKE '%systolic%'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= i.intime
    AND ce.charttime <= i.intime + INTERVAL 48 HOUR
  GROUP BY 
    i.stay_id
),
percentile_calc AS (
  SELECT 
    100.0 * SUM(CASE WHEN mean_systolic_bp <= 140 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_140
  FROM 
    systolic_bp_first_48
)
SELECT 
  percentile_140
FROM 
  percentile_calc;