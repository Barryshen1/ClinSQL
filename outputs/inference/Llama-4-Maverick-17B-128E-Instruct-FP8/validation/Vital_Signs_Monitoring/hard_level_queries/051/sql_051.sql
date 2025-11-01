WITH 
-- Step 1: Identify the cohort
cohort AS (
  SELECT p.subject_id, p.anchor_age, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON p.subject_id = icu.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 89 AND 99
),

-- Step 2: Identify ischemic stroke patients
ischemic_stroke AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE d_diag.long_title LIKE '%Ischemic stroke%'
),

-- Step 3: Calculate 48-hour instability score
instability_score AS (
  SELECT cohort.stay_id, 
         -- Example: Standard deviation of heart rate as a measure of instability
         STDDEV(ce.valuenum) AS instability,
         -- Example: Abnormal episodes (e.g., heart rate > 100 or < 60)
         SUM(CASE WHEN ce.valuenum > 100 OR ce.valuenum < 60 THEN 1 ELSE 0 END) AS abnormal_episodes
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN cohort ON ce.stay_id = cohort.stay_id
  WHERE ce.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label = 'Heart Rate')
  AND ce.charttime BETWEEN cohort.intime AND TIMESTAMP_ADD(cohort.intime, INTERVAL 48 HOUR)
  GROUP BY cohort.stay_id
),

-- Step 4: Calculate 95th percentile of instability score for ischemic stroke
percentile_95_instability AS (
  SELECT APPROX_QUANTILES(instability, 100)[OFFSET(95)] AS percentile_95
  FROM instability_score
  WHERE stay_id IN (SELECT stay_id FROM cohort JOIN ischemic_stroke ON cohort.hadm_id = ischemic_stroke.hadm_id)
),

-- Step 5: Compare metrics for top instability quartile
top_quartile AS (
  SELECT instability_score.stay_id, instability_score.instability, abnormal_episodes
  FROM instability_score
  JOIN cohort ON instability_score.stay_id = cohort.stay_id
  WHERE instability_score.instability > (SELECT percentile_95 FROM percentile_95_instability)
),

final_comparison AS (
  SELECT 
    COUNT(*) AS N,
    AVG(top_quartile.instability) AS mean_instability,
    AVG(top_quartile.abnormal_episodes) AS mean_abnormal_episodes,
    AVG(TIMESTAMP_DIFF(cohort.outtime, cohort.intime, HOUR)) AS mean_icu_los_hrs,
    -- Mortality calculation
    AVG(CASE WHEN adm.deathtime IS NOT NULL THEN 1 ELSE 0 END) AS mortality
  FROM top_quartile
  JOIN cohort ON top_quartile.stay_id = cohort.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON cohort.hadm_id = adm.hadm_id
  GROUP BY cohort.hadm_id IN (SELECT hadm_id FROM ischemic_stroke)
)

SELECT * FROM final_comparison;