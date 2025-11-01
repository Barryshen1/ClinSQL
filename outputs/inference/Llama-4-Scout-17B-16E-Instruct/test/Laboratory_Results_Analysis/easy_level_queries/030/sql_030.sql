WITH 
  -- Identify troponin lab item
  troponin_item AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE label LIKE '%Troponin%'
  ),
  
  -- Identify ACS patients
  acs_patients AS (
    SELECT DISTINCT a.subject_id, a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    WHERE p.gender = 'M'
    AND d.icd_code LIKE '%410%'  -- ACS ICD code, example for myocardial infarction
  )

-- Find minimum troponin for ACS male patients
SELECT 
  ap.subject_id,
  ap.hadm_id,
  MIN(le.valuenum) AS min_troponin
FROM acs_patients ap
JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON ap.hadm_id = le.hadm_id
JOIN troponin_item ti ON le.itemid = ti.itemid
GROUP BY ap.subject_id, ap.hadm_id;