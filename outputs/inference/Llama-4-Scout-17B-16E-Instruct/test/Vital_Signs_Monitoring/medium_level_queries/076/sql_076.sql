WITH 
-- Filter patient and ICU stays
patient_stays AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    ic.stay_id,
    ic.hadm_id,
    ic.intime,
    ic.outtime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON ic.subject_id = p.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 48 AND 58  
    AND ic.intime BETWEEN TIMESTAMP_SUB(ic.intime, INTERVAL 48 HOUR) AND ic.intime
),

-- Extract HR in first 48h with intime from icustays
hr_events AS (
  SELECT 
    ce.stay_id,
    ce.hadm_id,
    ce.value,
    ce.charttime,
    ic.intime  
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic 
      ON ce.stay_id = ic.stay_id AND ce.hadm_id = ic.hadm_id
  WHERE 
    ce.itemid = 220050  
    AND ce.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 48 HOUR)
),

-- Calculate average HR
avg_hr AS (
  SELECT 
    stay_id,
    hadm_id,
    AVG(CAST(value AS FLOAT64)) AS avg_hr_value
  FROM 
    hr_events
  GROUP BY 
    stay_id, hadm_id
),

-- Categorize HR
hr_categories AS (
  SELECT 
    stay_id,
    hadm_id,
    CASE
      WHEN avg_hr_value < 60 THEN '<60'
      WHEN avg_hr_value BETWEEN 60 AND 99 THEN '60–99'
      WHEN avg_hr_value BETWEEN 100 AND 119 THEN '100–119'
      ELSE '≥120'
    END AS hr_category
  FROM 
    avg_hr
),

-- Identify AKI 
aki_stays AS (
  SELECT 
    hadm_id,
    COUNT(*) > 0 AS has_aki
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    icd_code LIKE '%584%'  
  GROUP BY 
    hadm_id
)

-- Final calculation
SELECT 
  hr_category,
  COUNT(*) AS num_stays,
  SUM(CASE WHEN has_aki THEN 1 ELSE 0 END) AS num_aki,
  COUNT(*) * 100.0 / (SELECT COUNT(*) FROM hr_categories) AS percent_stays,
  SUM(CASE WHEN has_aki THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS aki_rate
FROM 
  hr_categories
  LEFT JOIN aki_stays ON hr_categories.hadm_id = aki_stays.hadm_id
GROUP BY 
  hr_category
ORDER BY 
  hr_category;