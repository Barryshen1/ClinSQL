WITH 
-- Identify cohort: female patients aged 43-53 with heart failure and ICU stay
cohort AS (
  SELECT DISTINCT a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 43 AND 53
    AND dd.long_title LIKE '%Heart Failure%'
),

-- Calculate 30-day mortality
mortality AS (
  SELECT 
    COUNTIF(deathtime IS NOT NULL AND deathtime <= TIMESTAMP_ADD(admittime, INTERVAL 30 DAY)) AS thirty_day_mortality_count,
    COUNT(hadm_id) AS total_patients
  FROM cohort
),

-- Calculate average LOS among survivors
los AS (
  SELECT 
    AVG(IF(deathtime IS NULL, DATE_DIFF(dischtime, admittime), NULL)) AS avg_los_survivors
  FROM cohort
),

-- Calculate median risk score (example: using hospital stay length as a simple risk score)
risk_scores AS (
  SELECT 
    hadm_id,
    DATE_DIFF(dischtime, admittime) AS risk_score
  FROM cohort
),

-- Calculate percentile of risk score
risk_percentile AS (
  SELECT 
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY risk_score) AS median_risk_score
  FROM risk_scores
),

-- Major complication rate (example: requires specific definitions or tables)
complication_rate AS (
  SELECT 
    COUNTIF(-- condition for major complication) AS major_complication_count,
    COUNT(hadm_id) AS total_patients_with_complications
  FROM cohort
)

SELECT 
  mortality.thirty_day_mortality_count,
  mortality.total_patients,
  los.avg_los_survivors,
  (SELECT median_risk_score FROM risk_percentile) AS median_risk_score,
  complication_rate.major_complication_count,
  complication_rate.total_patients_with_complications
FROM mortality, los, complication_rate;