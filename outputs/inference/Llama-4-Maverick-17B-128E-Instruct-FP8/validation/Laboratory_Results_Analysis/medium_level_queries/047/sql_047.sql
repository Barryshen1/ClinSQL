WITH 
-- Filter patients based on age and gender
eligible_patients AS (
  SELECT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 67 AND 77
),

-- Identify ACS admissions
acs_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM eligible_patients a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Acute coronary syndrome%' OR dicd.long_title LIKE '%Myocardial infarction%'
),

-- Get initial Troponin T measurements
troponin_t AS (
  SELECT a.subject_id, a.hadm_id, l.valuenum, ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY l.charttime) as rn
  FROM acs_admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON a.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  WHERE dl.label LIKE '%Troponin T%'
),

-- Calculate 99th percentile of Troponin T
troponin_t_percentile AS (
  SELECT APPROX_QUANTILES(valuenum, 100)[OFFSET(99)] as percentile_99th
  FROM troponin_t
  WHERE rn = 1
)

-- Report statistics for patients with initial Troponin T above the 99th percentile
SELECT 
  COUNT(DISTINCT subject_id) as patient_count,
  COUNT(DISTINCT hadm_id) as admission_count,
  AVG(valuenum) as mean_troponin_t,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] as median_troponin_t,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] as iqr_25_troponin_t,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] as iqr_75_troponin_t
FROM troponin_t
WHERE rn = 1 AND valuenum > (SELECT percentile_99th FROM troponin_t_percentile);