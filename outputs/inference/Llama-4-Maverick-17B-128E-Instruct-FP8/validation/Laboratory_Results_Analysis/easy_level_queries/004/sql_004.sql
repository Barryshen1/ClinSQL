WITH 
-- Step 1: Identify patients with sepsis
sepsis_patients AS (
  SELECT DISTINCT h.subject_id, h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON h.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON h.subject_id = p.subject_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 75 AND 77
    AND d_diag.long_title LIKE '%Sepsis%'  -- Simplified sepsis identification
),

-- Step 2: Calculate average platelet count over first 24 hours for each admission
platelet_counts AS (
  SELECT sp.hadm_id, AVG(le.valuenum) AS avg_platelet
  FROM sepsis_patients sp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON sp.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d_li ON le.itemid = d_li.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON sp.hadm_id = a.hadm_id
  WHERE d_li.label = 'Platelet Count'
    AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
  GROUP BY sp.hadm_id
)

-- Step 3: Calculate median of average platelet counts
SELECT 
  APPROX_QUANTILES(avg_platelet, 100)[OFFSET(50)] AS median_platelet_count
FROM platelet_counts;