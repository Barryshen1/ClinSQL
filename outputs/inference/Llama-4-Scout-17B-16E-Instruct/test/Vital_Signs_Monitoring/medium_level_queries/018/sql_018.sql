WITH 
patients_filtered AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE 
    p.gender = 'F' AND 
    p.anchor_age BETWEEN 75 AND 85
),

icustays_filtered AS (
  SELECT 
    i.stay_id, 
    i.subject_id, 
    i.intime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN 
    patients_filtered p ON i.subject_id = p.subject_id
),

systolic_bp AS (
  SELECT 
    ce.stay_id, 
    ce.charttime, 
    ce.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE 
    ce.itemid = 220050 AND 
    ce.valuenum IS NOT NULL
),

mean_sbp AS (
  SELECT 
    s.stay_id, 
    AVG(s.valuenum) AS mean_sbp
  FROM 
    systolic_bp s
  JOIN 
    icustays_filtered i ON s.stay_id = i.stay_id
  WHERE 
    s.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
  GROUP BY 
    s.stay_id
)

SELECT 
  APPROX_QUANTILES(mean_sbp, 100) AS quantiles
FROM 
  mean_sbp;