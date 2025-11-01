WITH spo2_averages AS (
  SELECT 
    i.stay_id,
    AVG(ce.valuenum) AS avg_spo2
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
    AND p.anchor_age BETWEEN 80 AND 90
    AND LOWER(di.label) LIKE '%spo2%'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100
  GROUP BY 
    i.stay_id
)
SELECT 
  (SUM(CASE WHEN avg_spo2 <= 88 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS percentile
FROM 
  spo2_averages;