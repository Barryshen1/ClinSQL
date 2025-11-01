WITH 
-- Define hs-TnT categories
hs_tnt_categories AS (
  SELECT 
    subject_id, 
    hadm_id, 
    valuenum,
    CASE 
      WHEN valuenum < 14 THEN 'normal'
      WHEN valuenum BETWEEN 14 AND 30 THEN 'borderline'
      ELSE 'myocardial injury'
    END AS category
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE 
    itemid = 43121  -- hs-TnT
    AND valuenum IS NOT NULL
),

-- Filter patients and admissions
patients_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.admission_type = 'acute'  -- Adjusting to 'acute' for AMI
)

-- Join and categorize
SELECT 
  h.category, 
  COUNT(DISTINCT h.hadm_id) AS count,
  ROUND(COUNT(DISTINCT h.hadm_id) * 100.0 / SUM(COUNT(DISTINCT h.hadm_id)) OVER (), 2) AS percentage
FROM 
  hs_tnt_categories h
JOIN 
  patients_admissions pa 
    ON h.subject_id = pa.subject_id AND h.hadm_id = pa.hadm_id
GROUP BY 
  h.category
ORDER BY 
  h.category;