WITH 
  -- Identify male patients aged 51-61
  eligible_patients AS (
    SELECT 
      p.subject_id,
      p.anchor_age
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 51 AND 61
  ),
  
  -- Calculate first 48-hour average SpO2 for each ICU stay
  spo2_values AS (
    SELECT 
      ic.stay_id,
      ic.intime,
      c.valuenum AS spo2_value
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` c 
        ON ic.subject_id = c.subject_id 
        AND ic.hadm_id = c.hadm_id 
        AND ic.stay_id = c.stay_id
    WHERE 
      c.itemid = 220050 
      AND c.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 48 HOUR)
  ),
  
  -- Average SpO2 per stay
  avg_spo2_per_stay AS (
    SELECT 
      stay_id,
      AVG(spo2_value) AS avg_spo2
    FROM 
      spo2_values
    GROUP BY 
      stay_id
  ),
  
  -- Categorize average SpO2
  categorized_spo2 AS (
    SELECT 
      stay_id,
      avg_spo2,
      CASE 
        WHEN avg_spo2 < 90 THEN '<90'
        WHEN avg_spo2 BETWEEN 90 AND 92 THEN '90-92'
        WHEN avg_spo2 BETWEEN 93 AND 95 THEN '93-95'
        ELSE '>95'
      END AS spo2_category
    FROM 
      avg_spo2_per_stay
  ),
  
  -- Identify AKI events (example based on creatinine itemid = 220052)
  aki_events AS (
    SELECT 
      ic.stay_id,
      COUNT(*) AS aki_count
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` c 
        ON ic.subject_id = c.subject_id 
        AND ic.hadm_id = c.hadm_id 
        AND ic.stay_id = c.stay_id
    WHERE 
      c.itemid = 220052 
      AND c.valuenum > 1.5  -- Example threshold for AKI
    GROUP BY 
      ic.stay_id
  )

-- Final query
SELECT 
  cs.spo2_category,
  COUNT(DISTINCT cs.stay_id) AS patient_count,
  COALESCE(SUM(aki.aki_count), 0) AS aki_count,
  SAFE_DIVIDE(COALESCE(SUM(aki.aki_count), 0), COUNT(DISTINCT cs.stay_id)) AS aki_rate
FROM 
  categorized_spo2 cs
LEFT JOIN 
  aki_events aki ON cs.stay_id = aki.stay_id
GROUP BY 
  cs.spo2_category;