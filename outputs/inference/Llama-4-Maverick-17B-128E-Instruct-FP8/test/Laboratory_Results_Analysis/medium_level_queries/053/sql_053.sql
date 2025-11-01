WITH 
relevant_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 68 AND 78
),
acs_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE d_diag.long_title LIKE '%Acute coronary syndrome%' OR diag.icd_code LIKE 'I24%' OR diag.icd_code LIKE 'I25%'
),
troponin_measurements AS (
  SELECT le.subject_id, le.hadm_id, le.valuenum, ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) as rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  WHERE le.itemid = 50821  
)
SELECT 
  COUNT(DISTINCT tm.subject_id) as patient_count,
  COUNT(DISTINCT tm.hadm_id) as admission_count,
  AVG(tm.valuenum) as mean_troponin,
  STDDEV(tm.valuenum) as stddev_troponin,
  MIN(tm.valuenum) as min_troponin,
  MAX(tm.valuenum) as max_troponin
FROM troponin_measurements tm
JOIN acs_admissions aa ON tm.hadm_id = aa.hadm_id
JOIN relevant_patients rp ON tm.subject_id = rp.subject_id
WHERE tm.rn = 1 AND tm.valuenum > 0.04;