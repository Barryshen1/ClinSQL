WITH sbp_averages AS (
  SELECT 
    ie.stay_id,
    AVG(ce.valuenum) AS avg_sbp
  FROM 
    physionet-data.mimiciv_3_1_icu.icustays ie
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p
    ON ie.subject_id = p.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.chartevents ce
    ON ie.stay_id = ce.stay_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND di.label = 'Systolic BP'
    AND ce.valueuom = 'mmHg'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= ie.intime
    AND ce.charttime <= ie.intime + INTERVAL 48 HOUR
  GROUP BY 
    ie.stay_id
)
SELECT 
  (SUM(CASE WHEN avg_sbp <= 160 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS percentile_of_160
FROM 
  sbp_averages;