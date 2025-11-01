WITH 
  -- Identify COPD patients
  copd_patients AS (
    SELECT DISTINCT a.subject_id, a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
    WHERE p.gender = 'F'
    AND icd.long_title LIKE '%COPD%'
  ),
  
  -- Extract serum creatinine measurements
  creatinine_measurements AS (
    SELECT le.subject_id, le.hadm_id, le.valuenum AS creatinine
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON le.itemid = dl.itemid
    WHERE dl.label = 'Creatinine'
    AND le.valuenum IS NOT NULL
  )

-- Find maximum peak serum creatinine in COPD patients
SELECT 
  MAX(cm.creatinine) AS max_peak_creatinine
FROM 
  copd_patients cp
  JOIN creatinine_measurements cm ON cp.hadm_id = cm.hadm_id AND cp.subject_id = cm.subject_id;