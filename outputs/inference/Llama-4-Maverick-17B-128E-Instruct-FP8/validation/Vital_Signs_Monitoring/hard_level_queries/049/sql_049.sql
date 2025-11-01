WITH 
-- Filter patients based on age and gender
eligible_patients AS (
  SELECT p.subject_id, p.gender, a.hadm_id, icu.stay_id, icu.intime,
         DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1), YEAR) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'M' AND DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1), YEAR) BETWEEN 78 AND 88
),

-- Identify sepsis patients (simplified; actual implementation may vary based on sepsis definition)
sepsis_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code IN ('A41.9', 'R65.20', 'R65.21')  -- Example ICD codes for sepsis; actual codes may vary
),

-- Filter eligible patients who are also in sepsis_patients
eligible_sepsis_patients AS (
  SELECT ep.subject_id, ep.hadm_id, ep.stay_id, ep.intime
  FROM eligible_patients ep
  JOIN sepsis_patients sp ON ep.hadm_id = sp.hadm_id
),

-- Calculate instability score (example; actual calculation depends on the score definition)
instability_scores AS (
  SELECT esp.subject_id, esp.hadm_id, esp.stay_id,
         MAX(CASE WHEN di.label = 'Heart Rate' THEN ce.valuenum ELSE NULL END) AS max_hr,
         MIN(CASE WHEN di.label = 'Systolic Blood Pressure' THEN ce.valuenum ELSE NULL END) AS min_sbp
  FROM eligible_sepsis_patients esp
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON esp.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE DATETIME_DIFF(ce.charttime, esp.intime, HOUR) <= 24
  GROUP BY esp.subject_id, esp.hadm_id, esp.stay_id
),

-- Calculate the actual instability score and percentile rank
scores AS (
  SELECT subject_id, hadm_id, stay_id,
         (max_hr + min_sbp) AS instability_score
  FROM instability_scores
),

percentile_ranks AS (
  SELECT instability_score,
         PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile_rank
  FROM scores
),

-- Quartile analysis
quartile_analysis AS (
  SELECT s.subject_id, s.hadm_id, s.stay_id, s.instability_score,
         NTILE(4) OVER (ORDER BY s.instability_score) AS quartile
  FROM scores s
),

-- Mean ICU LOS and hospital mortality for quartile 4
quartile_4_stats AS (
  SELECT AVG(icu.los) AS mean_icu_los,
         AVG(CASE WHEN a.dischtime IS NULL OR a.deathtime IS NOT NULL THEN 1 ELSE 0 END) AS hospital_mortality
  FROM quartile_analysis qa
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON qa.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON icu.hadm_id = a.hadm_id
  WHERE qa.quartile = 4
)

-- Final query to get percentile rank of score 85 and stats for quartile 4
SELECT 
  (SELECT percentile_rank FROM percentile_ranks WHERE instability_score <= 85 ORDER BY instability_score DESC LIMIT 1) AS percentile_rank_85,
  mean_icu_los,
  hospital_mortality
FROM quartile_4_stats;