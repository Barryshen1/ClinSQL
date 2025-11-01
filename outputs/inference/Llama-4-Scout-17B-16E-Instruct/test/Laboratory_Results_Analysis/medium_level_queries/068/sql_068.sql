WITH 
-- Define hs-Troponin T itemid and units
troponin_t_item AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%Troponin T%'
),

-- Select relevant patient and lab data
patient_labs AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    le.valuenum,
    le.valueuom
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON 
    p.subject_id = le.subject_id
  CROSS JOIN 
    troponin_t_item tti
  WHERE 
    le.itemid = tti.itemid
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 42 AND 52
)

-- Categorize troponin levels
SELECT 
  COUNT(CASE 
    WHEN valuenum < 0.014 THEN subject_id 
  END) AS normal,
  COUNT(CASE 
    WHEN valuenum >= 0.014 AND valuenum < 0.04 THEN subject_id 
  END) AS borderline,
  COUNT(CASE 
    WHEN valuenum >= 0.04 THEN subject_id 
  END) AS myocardial_injury
FROM 
  patient_labs;