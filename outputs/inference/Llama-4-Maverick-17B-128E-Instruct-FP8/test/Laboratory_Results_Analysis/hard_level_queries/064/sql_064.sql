WITH 
-- Step 1: Identify acute pancreatitis ICD codes
acute_pancreatitis_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%acute pancreatitis%'
  AND icd_version = 10
),

-- Step 2: Identify patients with acute pancreatitis
ap_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.anchor_age BETWEEN 65 AND 75
  AND p.gender = 'F'
  AND d.icd_code IN (SELECT icd_code FROM acute_pancreatitis_codes)
  AND a.admission_type = 'EMERGENCY'
),

-- Step 3: Calculate lab instability scores for the first 48 hours
lab_instability AS (
  SELECT ap.subject_id, ap.hadm_id,
         SUM(CASE 
             WHEN le.valuenum < dli.ref_range_lower OR le.valuenum > dli.ref_range_upper 
             THEN 1 
             ELSE 0 
             END) AS instability_score,
         SUM(CASE 
             WHEN (le.valuenum < dli.ref_range_lower OR le.valuenum > dli.ref_range_upper) 
             -- Assuming there's no direct 'Critical Lab Value' label; adjust according to actual data
             AND dli.label IN ('CRITICAL LAB VALUE', 'CRITICAL RESULT') 
             THEN 1 
             ELSE 0 
             END) AS critical_lab_count
  FROM ap_patients ap
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON ap.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
  WHERE le.charttime BETWEEN ap.admittime AND TIMESTAMP_ADD(ap.admittime, INTERVAL 48 HOUR)
  AND dli.ref_range_lower IS NOT NULL AND dli.ref_range_upper IS NOT NULL
  GROUP BY ap.subject_id, ap.hadm_id
),

-- Step 4: Calculate quintiles of lab instability scores
quintiles AS (
  SELECT hadm_id, instability_score, critical_lab_count,
         NTILE(5) OVER (ORDER BY instability_score) AS quintile
  FROM lab_instability
),

-- Step 5: Calculate required statistics per quintile
stats AS (
  SELECT q.quintile,
         COUNT(*) AS count,
         AVG(q.instability_score) AS mean_instability,
         AVG(TIMESTAMP_DIFF(ap.dischtime, ap.admittime, HOUR)) AS mean_los_hours,
         SUM(CASE WHEN ap.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate,
         AVG(q.critical_lab_count) AS avg_critical_labs, -- Direct average
         (SUM(q.critical_lab_count) / COUNT(*)) * 100 AS percent_critical_labs -- Percentage
  FROM quintiles q
  INNER JOIN ap_patients ap ON q.hadm_id = ap.hadm_id
  GROUP BY q.quintile
)

SELECT * FROM stats
ORDER BY quintile;