WITH 
-- Step 1: Filter patients
eligible_patients AS (
  SELECT p.subject_id, p.gender, icu.hadm_id, icu.stay_id, 
         p.anchor_age + EXTRACT(YEAR FROM icu.intime) - p.anchor_year AS age,
         icu.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON p.subject_id = icu.subject_id
  WHERE p.gender = 'M' 
    AND p.anchor_age + EXTRACT(YEAR FROM icu.intime) - p.anchor_year BETWEEN 85 AND 95
    AND icu.hadm_id IN (SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` WHERE icd_code IN ('J9600', 'J9601', 'J9602'))
),

-- Step 2: Calculate vital sign instability score
vital_signs AS (
  SELECT icu.stay_id, 
         MAX(CASE WHEN di.label = 'Heart Rate' THEN ce.valuenum END) AS max_hr,
         MIN(CASE WHEN di.label = 'Heart Rate' THEN ce.valuenum END) AS min_hr,
         MAX(CASE WHEN di.label = 'Systolic Blood Pressure' THEN ce.valuenum END) AS max_sbp,
         MIN(CASE WHEN di.label = 'Systolic Blood Pressure' THEN ce.valuenum END) AS min_sbp,
         MAX(CASE WHEN di.label = 'Respiratory Rate' THEN ce.valuenum END) AS max_rr,
         MIN(CASE WHEN di.label = 'Respiratory Rate' THEN ce.valuenum END) AS min_rr
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON icu.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE di.label IN ('Heart Rate', 'Systolic Blood Pressure', 'Respiratory Rate')
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY icu.stay_id
),

instability_score AS (
  SELECT stay_id, 
         (max_hr - min_hr) + (max_sbp - min_sbp) + (max_rr - min_rr) AS score
  FROM vital_signs
),

-- Step 3 & 4: Percentile rank and analysis for the most unstable quartile
quartile_analysis AS (
  SELECT stay_id, score,
         CASE WHEN PERCENT_RANK() OVER (ORDER BY score) >= 0.75 THEN 'Most Unstable Quartile' ELSE 'Other' END AS quartile_category
  FROM instability_score
),

-- Outcomes
outcomes AS (
  SELECT icu.stay_id, 
         icu.los,
         CASE WHEN adm.deathtime IS NOT NULL THEN 1 ELSE 0 END AS in_hospital_mortality
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON icu.hadm_id = adm.hadm_id
)

-- Final query
SELECT 
  -- Percentile rank of a score of 85
  (SELECT PERCENT_RANK() OVER (ORDER BY score) FROM instability_score WHERE score <= 85 ORDER BY score DESC LIMIT 1) AS percentile_rank_85,
  -- Average ICU LOS and in-hospital mortality for the most unstable quartile
  AVG(CASE WHEN qa.quartile_category = 'Most Unstable Quartile' THEN o.los END) AS avg_icu_los_most_unstable,
  AVG(CASE WHEN qa.quartile_category = 'Most Unstable Quartile' THEN o.in_hospital_mortality END) AS avg_in_hospital_mortality_most_unstable
FROM quartile_analysis qa
JOIN outcomes o ON qa.stay_id = o.stay_id;