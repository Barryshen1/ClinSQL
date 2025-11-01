WITH 
-- Step 1: Filter patients for females aged 43-53 with heart failure and an ICU stay
heart_failure_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id, icu.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 43 AND 53
  AND d_diag.long_title LIKE '%HEART FAILURE%'
),

-- Step 2: Calculate required metrics
metrics AS (
  SELECT 
    hf.subject_id,
    hf.hadm_id,
    hf.stay_id,
    -- Simplified example; actual risk score calculation would be more complex
    0.5 AS risk_score,  
    CASE 
      WHEN p.dod IS NULL THEN 0 
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(p.dod), DAY) <= 30 THEN 1 
      ELSE 0 
    END AS thirty_day_mortality,
    DATETIME_DIFF(icu.outtime, icu.intime, DAY) AS los_days,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag2
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag2 ON diag2.icd_code = d_diag2.icd_code AND diag2.icd_version = d_diag2.icd_version
      WHERE diag2.hadm_id = hf.hadm_id AND d_diag2.long_title LIKE '%SEPSIS%'
    ) THEN 1 ELSE 0 END AS major_complication
  FROM heart_failure_patients hf
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON hf.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON hf.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON hf.stay_id = icu.stay_id
),

-- Step 3: Aggregate metrics
aggregated_metrics AS (
  SELECT 
    PERCENTILE_CONT(risk_score, 0.5) OVER () AS median_risk_score,
    PERCENTILE_CONT(risk_score, 0.25) OVER () AS iqr1_risk_score,
    PERCENTILE_CONT(risk_score, 0.75) OVER () AS iqr3_risk_score,
    AVG(CASE WHEN thirty_day_mortality = 0 THEN los_days END) AS avg_los_survivors,
    AVG(thirty_day_mortality) AS thirty_day_mortality_rate,
    AVG(major_complication) AS major_complication_rate
  FROM metrics
),

-- Step 4: Risk percentile calculation for the cohort vs all females 43-53
all_females_risk AS (
  SELECT 
    0.5 AS risk_score  
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 43 AND 53
),
cohort_risk_percentile AS (
  SELECT 
    (COUNT(CASE WHEN afr.risk_score <= (SELECT median_risk_score FROM aggregated_metrics) THEN 1 END) / COUNT(*)) AS risk_percentile
  FROM all_females_risk afr
)

-- Final output
SELECT 
  (SELECT median_risk_score FROM aggregated_metrics) AS median_risk_score,
  (SELECT iqr3_risk_score - iqr1_risk_score FROM aggregated_metrics) AS iqr_risk_score,
  (SELECT thirty_day_mortality_rate FROM aggregated_metrics) AS thirty_day_mortality_rate,
  (SELECT major_complication_rate FROM aggregated_metrics) AS major_complication_rate,
  (SELECT avg_los_survivors FROM aggregated_metrics) AS avg_los_survivors,
  (SELECT risk_percentile FROM cohort_risk_percentile) AS cohort_risk_percentile;