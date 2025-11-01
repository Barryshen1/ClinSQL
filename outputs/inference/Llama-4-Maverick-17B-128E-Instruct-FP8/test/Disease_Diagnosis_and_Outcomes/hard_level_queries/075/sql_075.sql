WITH 
-- Filter patients based on age and gender
filtered_patients AS (
  SELECT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.dischtime, a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 44 AND 54
),

-- Identify patients with intracranial hemorrhage
ich_patients AS (
  SELECT DISTINCT f.subject_id, f.hadm_id, f.admittime, f.dischtime, f.deathtime
  FROM filtered_patients f
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON f.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Intracranial hemorrhage%'
),

-- Calculate risk score (for simplicity, let's assume we're using a basic risk score based on age and LOS)
risk_scores AS (
  SELECT subject_id, hadm_id, 
         -- Simplified risk score calculation for demonstration
         anchor_age + EXTRACT(DAY FROM (dischtime - admittime)) AS risk_score
  FROM filtered_patients
),

-- Calculate 90-day mortality
mortality_90d AS (
  SELECT subject_id, hadm_id, 
         CASE WHEN deathtime IS NOT NULL AND deathtime <= TIMESTAMP_ADD(admittime, INTERVAL 90 DAY) THEN 1 ELSE 0 END AS died_90d
  FROM ich_patients
),

-- Major complication rate (example: assuming a complication if LOS > 7 days)
complications AS (
  SELECT subject_id, hadm_id, 
         CASE WHEN EXTRACT(DAY FROM (dischtime - admittime)) > 7 THEN 1 ELSE 0 END AS major_complication
  FROM ich_patients
)

-- Main query to calculate required statistics
SELECT 
  -- Median (IQR) risk score for ICH patients
  APPROX_QUANTILES(r.risk_score, 100)[OFFSET(50)] AS median_risk_score,
  APPROX_QUANTILES(r.risk_score, 100)[OFFSET(25)] AS iqr1_risk_score,
  APPROX_QUANTILES(r.risk_score, 100)[OFFSET(75)] AS iqr3_risk_score,
  
  -- 90-day mortality for ICH patients
  AVG(m.died_90d) AS mortality_90d,
  
  -- Major complication rate for ICH patients
  AVG(c.major_complication) AS major_complication_rate,
  
  -- Median survivor LOS for ICH patients
  APPROX_QUANTILES(EXTRACT(DAY FROM (i.dischtime - i.admittime)), 100)[OFFSET(50)] AS median_survivor_los,
  
  -- Matched risk percentile (simplified, as actual calculation depends on the risk model used)
  (SELECT COUNT(*) FROM risk_scores WHERE risk_score <= (SELECT risk_score FROM risk_scores WHERE hadm_id IN (SELECT hadm_id FROM ich_patients))) / (SELECT COUNT(*) FROM risk_scores) * 100 AS matched_risk_percentile
FROM ich_patients i
INNER JOIN risk_scores r ON i.hadm_id = r.hadm_id
INNER JOIN mortality_90d m ON i.hadm_id = m.hadm_id
INNER JOIN complications c ON i.hadm_id = c.hadm_id;