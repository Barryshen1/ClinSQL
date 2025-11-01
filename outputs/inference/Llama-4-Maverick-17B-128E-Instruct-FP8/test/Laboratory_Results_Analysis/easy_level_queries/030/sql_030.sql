WITH 
-- Step 1 & 2: Identify male inpatients with ACS
acs_patients AS (
  SELECT DISTINCT p.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON p.subject_id = d.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE p.gender = 'M' AND diag.long_title LIKE '%myocardial infarction%'  -- Using MI as a proxy for ACS
),

-- Step 3: Identify itemid for troponin
troponin_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%Troponin%' AND (label LIKE '%Trop%' OR label LIKE '%T%')
),

-- Step 4: Find minimum troponin level for ACS patients
min_troponin AS (
  SELECT MIN(l.valuenum) AS min_troponin
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN acs_patients ON l.subject_id = acs_patients.subject_id AND l.hadm_id = acs_patients.hadm_id
  INNER JOIN troponin_itemids ON l.itemid = troponin_itemids.itemid
  WHERE l.valuenum IS NOT NULL
)

SELECT min_troponin
FROM min_troponin;