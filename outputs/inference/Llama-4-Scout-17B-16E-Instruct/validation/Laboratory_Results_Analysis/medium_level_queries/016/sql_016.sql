WITH 
-- Identify patients of interest
patients_of_interest AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 79 AND 89
    AND a.admission_type = 'Suspected ACS'  -- Assuming 'Suspected ACS' is the admission type
),

-- Get initial Troponin T levels
initial_troponin AS (
  SELECT 
    poi.subject_id, 
    poi.hadm_id, 
    le.valuenum AS troponin_level,
    ROW_NUMBER() OVER (PARTITION BY poi.subject_id, poi.hadm_id ORDER BY le.charttime) AS rn
  FROM 
    patients_of_interest poi
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON 
    poi.hadm_id = le.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
  ON 
    le.itemid = dli.itemid
  WHERE 
    dli.label LIKE '%Troponin%'
    AND le.valuenum IS NOT NULL
    AND poi.subject_id IS NOT NULL
),

-- Categorize Troponin T levels (assuming normal ranges, adjust as needed)
troponin_categories AS (
  SELECT 
    subject_id, 
    hadm_id, 
    troponin_level,
    CASE 
      WHEN troponin_level < 0.01 THEN 'Normal'
      WHEN troponin_level BETWEEN 0.01 AND 0.1 THEN 'Borderline'
      ELSE 'Elevated'
    END AS troponin_category
  FROM 
    initial_troponin
  WHERE 
    rn = 1
)

-- Calculate statistics
SELECT 
  troponin_category,
  COUNT(*) AS count,
  COUNT(*) / SUM(COUNT(*)) OVER () AS percentage,
  AVG(troponin_level) AS mean,
  APPROX_QUANTILES(troponin_level, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(troponin_level, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(troponin_level, 100)[OFFSET(75)] AS q3,
  APPROX_QUANTILES(troponin_level, 100)[OFFSET(75)] - APPROX_QUANTILES(troponin_level, 100)[OFFSET(25)] AS iqr
FROM 
  troponin_categories
GROUP BY 
  troponin_category;