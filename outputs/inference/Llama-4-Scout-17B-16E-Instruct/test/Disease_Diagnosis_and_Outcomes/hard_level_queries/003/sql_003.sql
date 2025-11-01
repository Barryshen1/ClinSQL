WITH 
-- Identify patients of interest
patients_of_interest AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND a.hadm_id IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_code LIKE '415.1%'  -- Pulmonary embolism ICD-9 code
        OR icd_code LIKE 'I26.%'  -- Pulmonary embolism ICD-10 code
    )
),

-- Calculate 90-day mortality
mortality AS (
  SELECT 
    subject_id,
    hadm_id,
    CASE 
      WHEN hospital_expire_flag = 1 OR (deathtime IS NOT NULL AND TIMESTAMP_DIFF(deathtime, admittime, DAY) <= 90) THEN 1
      ELSE 0
    END AS ninety_day_mortality
  FROM 
    patients_of_interest
),

-- Identify AKI and ARDS
aki_ards AS (
  SELECT 
    ce.subject_id,
    ce.hadm_id,
    CASE 
      WHEN ce.itemid = 220050 AND ce.valuenum > 1.5 THEN 1  -- AKI based on creatinine
      ELSE 0
    END AS aki,
    CASE 
      WHEN ce.itemid = 220179 AND ce.valuenum > 300 THEN 1  -- ARDS based on P/F ratio
      ELSE 0
    END AS ards
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN 
    patients_of_interest poi ON ce.subject_id = poi.subject_id AND ce.hadm_id = poi.hadm_id
),

-- Calculate LOS
los AS (
  SELECT 
    subject_id,
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los
  FROM 
    patients_of_interest
  WHERE 
    hospital_expire_flag = 0 AND deathtime IS NULL  -- Survivor
),

-- Combined data
combined_data AS (
  SELECT 
    poi.hadm_id,
    m.ninety_day_mortality,
    COALESCE(aki.aki, 0) AS aki,
    COALESCE(aki.ards, 0) AS ards,
    COALESCE(l.los, 0) AS los
  FROM 
    patients_of_interest poi
  LEFT JOIN 
    mortality m ON poi.hadm_id = m.hadm_id
  LEFT JOIN 
    aki_ards aki ON poi.hadm_id = aki.hadm_id
  LEFT JOIN 
    los l ON poi.hadm_id = l.hadm_id
),

-- Calculate risk quintiles and statistics
quintile_stats AS (
  SELECT 
    NTILE(5) OVER (ORDER BY cd.hadm_id) AS risk_quintile,
    cd.ninety_day_mortality,
    cd.aki,
    cd.ards,
    cd.los
  FROM 
    combined_data cd
)

SELECT 
  risk_quintile,
  AVG(ninety_day_mortality) AS ninety_day_mortality_rate,
  -- General 70–80 female 90‑day mortality for comparison
  (SELECT 
     AVG(ninety_day_mortality)
   FROM 
     mortality
   WHERE 
     hadm_id IN (
       SELECT 
         hadm_id
       FROM 
         patients_of_interest
     )) AS general_ninety_day_mortality,
  AVG(aki) AS aki_rate,
  AVG(ards) AS ards_rate,
  PERCENTILE_CONT(0.5)(los) OVER (PARTITION BY risk_quintile) AS median_survivor_los
FROM 
  quintile_stats
GROUP BY 
  risk_quintile;