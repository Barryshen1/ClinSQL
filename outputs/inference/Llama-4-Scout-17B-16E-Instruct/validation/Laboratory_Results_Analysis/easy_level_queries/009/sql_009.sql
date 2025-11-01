WITH 
  -- Identify female patients
  female_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F'
  ),
  
  -- Identify admissions for female patients with ACS
  acs_admissions AS (
    SELECT a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN female_patients fp ON a.subject_id = fp.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    WHERE d.icd_code LIKE '410%' OR d.icd_code LIKE '411%'  -- Example ICD codes for ACS
  ),
  
  -- Identify troponin lab events
  troponin_events AS (
    SELECT le.hadm_id, le.valuenum AS troponin_level
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON le.itemid = dl.itemid
    WHERE dl.label LIKE '%Troponin%' AND le.valuenum IS NOT NULL
  ),
  
  -- Identify nadir troponin for each admission
  nadir_troponin AS (
    SELECT hadm_id, MIN(troponin_level) AS nadir_troponin
    FROM troponin_events
    GROUP BY hadm_id
  ),
  
  -- Filter for ACS admissions and select nadir troponin
  acs_nadir_troponin AS (
    SELECT n.nadir_troponin
    FROM nadir_troponin n
    JOIN acs_admissions aa ON n.hadm_id = aa.hadm_id
  )

SELECT 
  APPROX_QUANTILES(nadir_troponin, 100)[OFFSET(25)] AS percentile_25
FROM acs_nadir_troponin;