WITH 
-- Define DVT ICD codes
dvt_icd_codes AS (
  SELECT 'ICD-9' AS icd_version, '453.1' AS icd_code UNION ALL
  SELECT 'ICD-10' AS icd_version, 'I80' AS icd_code
),

-- Identify patients with DVT
patients_with_dvt AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    p.gender,
    a.admittime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN 
    dvt_icd_codes c ON d.icd_code = c.icd_code AND d.icd_version = c.icd_version
  WHERE 
    p.gender = 'M' AND 
    p.anchor_age BETWEEN 71 AND 81
),

-- Calculate 90-day mortality
mortality AS (
  SELECT 
    subject_id, 
    hadm_id, 
    MIN(CASE WHEN deathtime IS NOT NULL AND deathtime <= TIMESTAMP_ADD(admittime, INTERVAL 90 DAY) THEN 1 ELSE 0 END) AS died_90_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
  GROUP BY 
    subject_id, 
    hadm_id
),

-- Assume a risk score calculation; for simplicity, let's use a placeholder
risk_scores AS (
  SELECT 
    hadm_id,
    -- Placeholder for actual risk score calculation
    10 AS risk_score
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- Calculate median and IQR for risk scores
risk_score_stats AS (
  SELECT 
    APPROX_QUANTILES(risk_score, 100)[OFFSET(50)] AS median_risk_score,
    APPROX_QUANTILES(risk_score, 100)[OFFSET(75)] - APPROX_QUANTILES(risk_score, 100)[OFFSET(25)] AS iqr_risk_score
  FROM 
    risk_scores
)

-- Final query
SELECT 
  COUNT(DISTINCT CASE WHEN m.died_90_days = 1 THEN p.hadm_id END) AS num_deaths_90_days,
  COUNT(DISTINCT p.hadm_id) AS total_patients,
  rs.median_risk_score,
  rs.iqr_risk_score
FROM 
  patients_with_dvt p
  JOIN mortality m ON p.hadm_id = m.hadm_id
  JOIN risk_scores r ON p.hadm_id = r.hadm_id
  CROSS JOIN risk_score_stats rs;