WITH heart_rate_data AS (
  SELECT 
    ce.valuenum AS heart_rate
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.stay_id = ce.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
    AND di.label IN ('Heart Rate', 'HR', 'Pulse')
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 300
    AND ce.charttime >= icu.intime + INTERVAL '48' HOUR
)

SELECT 
  APPROX_QUANTILES(heart_rate, 4)[OFFSET(3)] - APPROX_QUANTILES(heart_rate, 4)[OFFSET(1)] AS iqr_heart_rate
FROM 
  heart_rate_data;