WITH 
-- Step 1: Define the cohort
cohort AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 44 AND 54
  AND d_diag.long_title LIKE '%Intracranial hemorrhage%'
),

-- Step 2: Calculate composite risk score (simplified example)
risk_score AS (
  SELECT subject_id, hadm_id, anchor_age,
         -- Simplified example: using age as a proxy for risk score
         CAST(anchor_age AS FLOAT64) AS risk_score
  FROM cohort
),

-- Step 3: Stratify by risk score quartile
quartiles AS (
  SELECT subject_id, hadm_id, risk_score,
         NTILE(4) OVER (ORDER BY risk_score) AS quartile
  FROM risk_score
),

-- Step 4: Calculate required metrics
metrics AS (
  SELECT q.quartile,
         COUNT(DISTINCT q.hadm_id) AS patient_count,
         SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT q.hadm_id) AS in_hospital_mortality,
         -- Example complication ICD codes; replace with actual codes
         SUM(CASE WHEN diag.icd_code IN ('I61', 'I62', 'I63', 'I64') THEN 1 ELSE 0 END) / COUNT(DISTINCT q.hadm_id) AS neurologic_complication_rate,
         SUM(CASE WHEN diag.icd_code IN ('I21', 'I22', 'I24', 'I25') THEN 1 ELSE 0 END) / COUNT(DISTINCT q.hadm_id) AS cardiac_complication_rate
  FROM quartiles q
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON q.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  GROUP BY q.quartile
),

-- Step 5: Calculate median LOS for survivors
median_los AS (
  SELECT q.quartile,
         PERCENTILE_CONT(DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24, 0.5) AS median_los_survivors
  FROM quartiles q
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON q.hadm_id = a.hadm_id
  WHERE a.hospital_expire_flag = 0
  GROUP BY q.quartile
)

-- Combine metrics and median LOS
SELECT m.quartile, m.patient_count, m.in_hospital_mortality, 
       m.neurologic_complication_rate, m.cardiac_complication_rate, 
       l.median_los_survivors
FROM metrics m
JOIN median_los l ON m.quartile = l.quartile
ORDER BY m.quartile;