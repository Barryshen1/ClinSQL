WITH 
  -- Identify male patients aged 89-99
  eligible_patients AS (
    SELECT p.subject_id, p.anchor_age, a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    WHERE p.gender = 'M' AND p.anchor_age BETWEEN 89 AND 99
  ),
  
  -- Identify ischemic stroke patients
  ischemic_stroke_patients AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code IN (
      '433.1', '433.11', '433.12', '433.13', '433.14', '433.15', '433.16', '433.17', '433.18', '433.19'
    ) AND icd_version = 'ICD-9'
  ),
  
  -- Calculate instability score (example: using heart rate variability)
  instability_scores AS (
    SELECT 
      ce.subject_id, 
      ce.hadm_id, 
      ce.stay_id,
      -- Example instability score calculation (may need adjustment)
      AVG(CASE 
        WHEN d.label = 'Heart Rate' THEN ABS(VALUENUM - LAG(VALUENUM) OVER (PARTITION BY ce.subject_id, ce.hadm_id ORDER BY ce.charttime))
        ELSE 0
      END) AS instability_score
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON ce.itemid = d.itemid
    WHERE ce.charttime > (SELECT intime FROM `physionet-data.mimiciv_3_1_icu.icustays` ic WHERE ic.hadm_id = ce.hadm_id AND ic.stay_id = ce.stay_id)
      AND ce.charttime < (SELECT outtime FROM `physionet-data.mimiciv_3_1_icu.icustays` ic WHERE ic.hadm_id = ce.hadm_id AND ic.stay_id = ce.stay_id)
    GROUP BY ce.subject_id, ce.hadm_id, ce.stay_id
  ),
  
  -- Filter ischemic stroke patients with instability scores
  ischemic_stroke_scores AS (
    SELECT 
      es.subject_id, 
      es.hadm_id, 
      es.instability_score
    FROM instability_scores es
    JOIN ischemic_stroke_patients isp ON es.hadm_id = isp.hadm_id
  ),
  
  -- Calculate 95th percentile instability score for ischemic stroke
  percentile_score AS (
    SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS percentile_95
    FROM ischemic_stroke_scores
  ),
  
  -- Identify top instability quartile patients
  top_instability_quartile AS (
    SELECT subject_id, hadm_id, instability_score
    FROM ischemic_stroke_scores
    WHERE instability_score > (SELECT percentile_95 FROM percentile_score)
  ),

  -- General ICU patient data
  general_icu_patients AS (
    SELECT 
      ic.stay_id,
      ic.hadm_id,
      ic.subject_id,
      AVG(CASE 
        WHEN d.label = 'Heart Rate' THEN VALUENUM
        ELSE 0
      END) AS mean_heart_rate,
      COUNT(CASE 
        WHEN d.label = 'Heart Rate' AND VALUENUM > 100 THEN 1
        ELSE NULL
      END) AS abnormal_episodes,
      TIMESTAMPDIFF(HOUR, ic.intime, ic.outtime) AS icu_los_hrs,
      CASE 
        WHEN ic.outtime IS NULL THEN 1
        ELSE 0
      END AS mortality
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ic.stay_id = ce.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON ce.itemid = d.itemid
    GROUP BY ic.stay_id, ic.hadm_id, ic.subject_id, ic.intime, ic.outtime
  )

-- Final comparison
SELECT 
  'Ischemic Stroke' AS patient_type,
  COUNT(*) AS N,
  AVG(instability_score) AS mean_instability,
  AVG(0) AS mean_abnormal_episodes,
  AVG(0) AS mean_icu_los_hrs,
  SUM(0) AS mortality
FROM top_instability_quartile

UNION ALL

SELECT 
  'General ICU' AS patient_type,
  COUNT(*) AS N,
  AVG(mean_heart_rate) AS mean_instability,
  AVG(abnormal_episodes) AS mean_abnormal_episodes,
  AVG(icu_los_hrs) AS mean_icu_los_hrs,
  SUM(mortality) AS mortality
FROM general_icu_patients;