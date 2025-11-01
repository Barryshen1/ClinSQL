WITH patient_age AS (
  SELECT 
    i.stay_id,
    p.gender,
    i.intime,
    EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age AS age
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
),
systolic_bp AS (
  SELECT 
    c.stay_id,
    AVG(c.valuenum) AS avg_sbp
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN 
    patient_age pa ON c.stay_id = pa.stay_id
  WHERE 
    c.itemid = 220050  
    AND c.charttime BETWEEN pa.intime AND TIMESTAMP_ADD(pa.intime, INTERVAL 48 HOUR)
    AND pa.gender = 'F'
    AND pa.age BETWEEN 38 AND 48
  GROUP BY 
    c.stay_id
)
SELECT 
  COUNTIF(avg_sbp <= 130) * 100.0 / COUNT(*) AS percentile
FROM 
  systolic_bp;