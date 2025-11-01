WITH 
-- Step 1: Identify patients with acute pancreatitis
acute_pancreatitis_patients AS (
  SELECT DISTINCT h.subject_id, h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON h.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON h.subject_id = p.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 35 AND 45
  AND dicd.long_title LIKE '%Acute pancreatitis%'
),

-- Step 2: Calculate diagnosis count and major complication flags
patient_risk_score AS (
  SELECT ap.subject_id, ap.hadm_id,
         COUNT(DISTINCT d.icd_code) AS diagnosis_count,
         SUM(CASE WHEN dicd.long_title LIKE '% complication%' OR dicd.long_title LIKE '%failure%' THEN 1 ELSE 0 END) AS major_complication_flags,
         MAX(a.hospital_expire_flag) AS hospital_expire_flag,
         DATETIME_DIFF(MAX(a.dischtime), MIN(a.admittime), SECOND) AS los_in_seconds
  FROM acute_pancreatitis_patients ap
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON ap.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON ap.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  GROUP BY ap.subject_id, ap.hadm_id
),

-- Step 3: Calculate risk score and stratify into quartiles
risk_score_quartiles AS (
  SELECT subject_id, hadm_id, hospital_expire_flag, los_in_seconds, major_complication_flags,
         diagnosis_count + 5 * major_complication_flags AS risk_score,
         NTILE(4) OVER (ORDER BY diagnosis_count + 5 * major_complication_flags) AS risk_quartile
  FROM patient_risk_score
)

-- Step 4: Calculate required metrics for each quartile and overall
SELECT 
  risk_quartile,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) / COUNT(*) AS in_hospital_mortality,
  SUM(CASE WHEN major_complication_flags > 0 THEN 1 ELSE 0 END) / COUNT(*) AS major_complication_rate,
  APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_in_seconds ELSE NULL END, 100)[OFFSET(50)] / (24*3600) AS median_survivor_los_days
FROM risk_score_quartiles
GROUP BY ROLLUP(risk_quartile)
ORDER BY risk_quartile;