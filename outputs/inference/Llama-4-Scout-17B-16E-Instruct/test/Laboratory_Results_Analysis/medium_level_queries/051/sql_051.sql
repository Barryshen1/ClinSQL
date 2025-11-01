WITH 
-- Identify hs-TnT itemid
hs_tnt_itemid AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
  WHERE label LIKE '%hs-TnT%'
),

-- Filter patients and get admission information
patients_info AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    p.gender, 
    p.anchor_age,
    a.admission_type
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 80 AND 90
    AND a.admission_type = 'Emergency'  -- Assuming ACS patients are admitted as Emergency
),

-- Get hs-TnT lab results
hs_tnt_results AS (
  SELECT 
    le.subject_id, 
    le.hadm_id, 
    le.charttime, 
    le.valuenum, 
    le.value
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN 
    hs_tnt_itemid hti 
  ON le.itemid = hti.itemid
),

-- Categorize hs-TnT results 
hs_tnt_categories AS (
  SELECT 
    subject_id, 
    hadm_id, 
    valuenum,
    value,
    CASE 
      WHEN valuenum < 10 THEN 'Normal'
      WHEN valuenum < 100 THEN 'Borderline'
      ELSE 'Myocardial Injury'
    END AS category
  FROM 
    hs_tnt_results
)

-- Calculate statistics
SELECT 
  htc.category,
  COUNT(DISTINCT htc.hadm_id) AS count,
  COUNT(DISTINCT htc.hadm_id) / SUM(COUNT(DISTINCT htc.hadm_id)) OVER () AS percentage,
  AVG(DATE_DIFF(CAST(pi.dischtime AS DATE), CAST(pi.admittime AS DATE), DAY)) AS mean_hospital_length_of_stay
FROM 
  patients_info pi
JOIN 
  hs_tnt_categories htc 
  ON pi.hadm_id = htc.hadm_id
GROUP BY 
  htc.category;