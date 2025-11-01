WITH patient_spo2 AS (
  SELECT 
    p.subject_id,
    AVG(ce.valuenum) AS mean_spo2
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu ON p.subject_id = icu.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON icu.stay_id = ce.stay_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND ce.itemid = 220277  
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY 
    p.subject_id
),
percentile_calc AS (
  SELECT 
    mean_spo2,
    PERCENT_RANK() OVER (ORDER BY mean_spo2) AS percentile
  FROM 
    patient_spo2
)
SELECT 
  percentile
FROM 
  percentile_calc
WHERE 
  mean_spo2 <= 92
ORDER BY 
  percentile DESC
LIMIT 1;