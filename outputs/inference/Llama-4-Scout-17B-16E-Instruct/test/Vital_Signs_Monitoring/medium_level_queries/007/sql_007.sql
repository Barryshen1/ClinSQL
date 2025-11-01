WITH 
  -- Filter for female patients aged 80-90 and relevant ICU stays
  eligible_patients AS (
    SELECT p.subject_id, p.anchor_age, p.gender
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE p.gender = 'F' AND p.anchor_age BETWEEN 80 AND 90
  ),
  
  -- Extract SpO2 data for eligible patients
  spo2_data AS (
    SELECT 
      ce.stay_id,
      AVG(ce.valuenum) AS avg_spo2
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN 
      eligible_patients ep ON ce.subject_id = ep.subject_id
    WHERE 
      ce.itemid = 220050  -- SpO2 itemid
    GROUP BY 
      ce.stay_id
  )

SELECT 
  COUNT(*) AS total_stays,
  SUM(CASE WHEN avg_spo2 <= 88 THEN 1 ELSE 0 END) AS stays_below_88,
  (SUM(CASE WHEN avg_spo2 <= 88 THEN 1 ELSE 0 END) * 1.0 / COUNT(*)) * 100 AS percentage_below_88
FROM 
  spo2_data;