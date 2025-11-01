WITH sbp_first_24h AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    AVG(ce.valuenum) AS avg_sbp_24h
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
    AND p.anchor_age BETWEEN 45 AND 55
    AND LOWER(di.label) LIKE '%systolic%'  -- captures 'Systolic BP', 'SBP', etc.
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 50 AND ce.valuenum < 300  -- reasonable SBP range
    AND ce.charttime >= i.intime
    AND ce.charttime < i.intime + INTERVAL '24' HOUR
  GROUP BY 
    i.stay_id, i.subject_id
),
patient_avg_sbp AS (
  SELECT 
    subject_id,
    avg_sbp_24h
  FROM 
    sbp_first_24h
)
SELECT 
  CASE 
    WHEN avg_sbp_24h < 140 THEN '<140'
    WHEN avg_sbp_24h >= 140 AND avg_sbp_24h <= 159 THEN '140-159'
    WHEN avg_sbp_24h >= 160 THEN '>=160'
  END AS sbp_category,
  COUNT(DISTINCT subject_id) AS patient_count
FROM 
  patient_avg_sbp
GROUP BY 
  sbp_category
ORDER BY 
  sbp_category;