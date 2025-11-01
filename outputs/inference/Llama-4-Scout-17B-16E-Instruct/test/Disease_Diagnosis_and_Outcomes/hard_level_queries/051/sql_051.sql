WITH 
-- Identify acute pancreatitis patients and calculate risk score
acute_pancreatitis AS (
  SELECT 
    a.subject_id, 
    a.hadm_id,
    COUNT(DISTINCT di.icd_code) AS diagnosis_count,
    SUM(CASE WHEN di.icd_code NOT IN ('577.0', 'K85.0') THEN 1 ELSE 0 END) AS major_complication_flags
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  WHERE 
    p.gender = 'M' AND 
    p.anchor_age BETWEEN 35 AND 45 AND
    di.icd_code IN ('577.0', 'K85.0')  -- ICD-9 and ICD-10 codes for acute pancreatitis
  GROUP BY 
    a.subject_id, 
    a.hadm_id
),
-- Calculate risk score
risk_score AS (
  SELECT 
    subject_id, 
    hadm_id,
    diagnosis_count,
    major_complication_flags,
    diagnosis_count + 5 * major_complication_flags AS risk_score
  FROM 
    acute_pancreatitis
),
-- Stratify into quartiles
quartiles AS (
  SELECT 
    subject_id, 
    hadm_id,
    diagnosis_count,
    major_complication_flags,
    risk_score,
    NTILE(4) OVER (ORDER BY risk_score) AS quartile
  FROM 
    risk_score
),
-- Calculate outcomes
outcomes AS (
  SELECT 
    q.quartile,
    AVG(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_mortality,
    AVG(CASE WHEN di.icd_code NOT IN ('577.0', 'K85.0') THEN 1 ELSE 0 END) AS major_complication_rate,
    APPROX_QUANTILES(TIMESTAMPDIFF(DAY, a.admittime, a.dischtime), 1000)[OFFSET(500)] AS median_survivor_los
  FROM 
    quartiles q
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON q.hadm_id = a.hadm_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  GROUP BY 
    q.quartile
)
-- Final result
SELECT 
  quartile,
  in_hospital_mortality,
  major_complication_rate,
  median_survivor_los
FROM 
  outcomes
ORDER BY 
  quartile;