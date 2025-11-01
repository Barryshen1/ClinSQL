WITH 
-- Define age range and admission types of interest
patient_filters AS (
  SELECT p.subject_id, p.anchor_age, p.gender, a.admittime, a.dischtime, a.deathtime, a.admission_type, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 35 AND 45
  AND (a.admission_type = 'elective' OR a.admission_type = 'urgent' OR a.admission_type = 'emergency')
  AND (LOWER(a.admission_location) LIKE '%chest pain%' OR LOWER(a.admission_location) LIKE '%ami%' 
       OR LOWER(a.admission_type) LIKE '%chest pain%' OR LOWER(a.admission_type) LIKE '%ami%')
),

-- Retrieve itemid for hs-TnT
hs_tnt_item AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),

-- Get first hs-TnT measurement for each patient
first_hs_tnt AS (
  SELECT lf.subject_id, lf.hadm_id, lf.charttime, lf.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` lf
  JOIN hs_tnt_item hti ON lf.itemid = hti.itemid
  WHERE lf.valuenum IS NOT NULL
)

-- Categorize hs-TnT levels and count
SELECT 
  COUNT(CASE WHEN valuenum < 0.01 THEN 1 ELSE NULL END) AS normal,
  COUNT(CASE WHEN valuenum BETWEEN 0.01 AND 0.1 THEN 1 ELSE NULL END) AS borderline,
  COUNT(CASE WHEN valuenum > 0.1 THEN 1 ELSE NULL END) AS myocardial_injury
FROM first_hs_tnt fht
JOIN patient_filters pf ON fht.subject_id = pf.subject_id AND fht.hadm_id = pf.hadm_id;