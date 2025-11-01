WITH 
-- Identify Troponin I itemid
troponin_i AS (
  SELECT itemid, label 
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
  WHERE label LIKE '%Troponin I%'
),

-- Select patients of interest
patients_of_interest AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.admission_type
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 90 AND 100
    AND a.admission_type = 'Emergency'  
    AND a.admission_location = 'Chest Pain'  
),

-- Identify initial elevated Troponin I
initial_troponin AS (
  SELECT it.subject_id, it.hadm_id, 
         MAX(CASE WHEN ti.label LIKE '%Troponin I%' AND it.valuenum > 0.04 THEN it.valuenum END) AS initial_troponin_level
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` it
  JOIN troponin_i ti ON it.itemid = ti.itemid
  WHERE it.subject_id IN (SELECT subject_id FROM patients_of_interest)
  GROUP BY it.subject_id, it.hadm_id
  HAVING MAX(CASE WHEN ti.label LIKE '%Troponin I%' AND it.valuenum > 0.04 THEN it.valuenum END) IS NOT NULL
)

-- Calculate percentiles and range
SELECT 
  APPROX_QUANTILES(initial_troponin_level, 0.25)[OFFSET(0)] AS p25,
  APPROX_QUANTILES(initial_troponin_level, 0.5)[OFFSET(0)] AS p50,
  APPROX_QUANTILES(initial_troponin_level, 0.75)[OFFSET(0)] AS p75,
  MIN(initial_troponin_level) AS min_value,
  MAX(initial_troponin_level) AS max_value
FROM initial_troponin;