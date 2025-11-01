WITH 
  -- Get patient demographic information
  patient_info AS (
    SELECT 
      p.subject_id,
      p.gender,
      p.anchor_age,
      p.dod
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
  ),
  
  -- Get ICU stay information
  icu_stay_info AS (
    SELECT 
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      i.intime,
      i.outtime,
      i.first_careunit,
      i.last_careunit,
      i.los
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` i
  ),
  
  -- Get SpO2 measurements
  spo2_measurements AS (
    SELECT 
      c.subject_id,
      c.hadm_id,
      c.stay_id,
      c.charttime,
      c.itemid,
      c.value,
      c.valuenum
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` c
    WHERE 
      c.itemid = 220050  -- SpO2
  ),
  
  -- Calculate first-24h per-stay average SpO2
  avg_spo2 AS (
    SELECT 
      s.subject_id,
      s.stay_id,
      AVG(s.valuenum) AS avg_spo2
    FROM 
      spo2_measurements s
    JOIN 
      icu_stay_info i ON s.subject_id = i.subject_id AND s.stay_id = i.stay_id
    WHERE 
      s.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
    GROUP BY 
      s.subject_id, s.stay_id
  ),
  
  -- Filter patients by age and gender
  filtered_patients AS (
    SELECT 
      p.subject_id,
      p.gender,
      p.anchor_age
    FROM 
      patient_info p
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 90 AND 100
  ),
  
  -- Join with ICU stay information and average SpO2
  joined_info AS (
    SELECT 
      f.subject_id,
      i.stay_id,
      a.avg_spo2
    FROM 
      filtered_patients f
    JOIN 
      icu_stay_info i ON f.subject_id = i.subject_id
    JOIN 
      avg_spo2 a ON f.subject_id = a.subject_id AND i.stay_id = a.stay_id
  ),
  
  -- Categorize patients by average SpO2
  categorized_patients AS (
    SELECT 
      subject_id,
      stay_id,
      avg_spo2,
      CASE 
        WHEN avg_spo2 < 90 THEN '<90'
        WHEN avg_spo2 BETWEEN 90 AND 92 THEN '90–92'
        WHEN avg_spo2 BETWEEN 93 AND 95 THEN '93–95'
        ELSE '>95'
      END AS spo2_category
    FROM 
      joined_info
  ),
  
  -- Calculate AKI
  aki_patients AS (
    SELECT 
      c.subject_id,
      c.stay_id,
      COUNT(DISTINCT c.itemid) > 0 AS has_aki
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` c
    WHERE 
      c.itemid IN (220050, 220179)  -- SCr or Creatinine
      AND c.valuenum > 1.5 
    GROUP BY 
      c.subject_id, c.stay_id
  )

-- Calculate required statistics
SELECT 
  cp.spo2_category,
  COUNT(cp.subject_id) AS N,
  AVG(cp.avg_spo2) AS mean,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY cp.avg_spo2) AS median,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY cp.avg_spo2) - 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY cp.avg_spo2) AS IQR,
  SUM(CASE 
        WHEN ap.has_aki THEN 1 
        ELSE 0 
      END) / COUNT(cp.subject_id) AS AKI_rate
FROM 
  categorized_patients cp
  LEFT JOIN aki_patients ap ON cp.subject_id = ap.subject_id AND cp.stay_id = ap.stay_id
GROUP BY 
  cp.spo2_category;