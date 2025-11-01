WITH 
rrt_patients AS (
  SELECT DISTINCT p.subject_id, ie.hadm_id, ie.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON p.subject_id = ie.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON ie.stay_id = pe.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 88 AND 98
    AND (di.label LIKE '%RRT%' OR di.label LIKE '%Dialysis%')
),

instability_scores AS (
  SELECT rrt.subject_id, rrt.hadm_id, rrt.stay_id,
         MAX(ce.valuenum) AS max_instability_score
  FROM rrt_patients rrt
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON rrt.stay_id = ie.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON rrt.stay_id = ce.stay_id
  WHERE ce.charttime BETWEEN ie.intime AND TIMESTAMP_ADD(ie.intime, INTERVAL 72 HOUR)
  GROUP BY rrt.subject_id, rrt.hadm_id, rrt.stay_id
),

percentile_calc AS (
  SELECT 
    PERCENT_RANK() OVER (ORDER BY max_instability_score) AS percentile_rank_85
  FROM instability_scores
),

most_unstable AS (
  SELECT subject_id, hadm_id, stay_id, max_instability_score,
         PERCENT_RANK() OVER (ORDER BY max_instability_score DESC) AS unstable_percentile
  FROM instability_scores
),

icu_los_mortality AS (
  SELECT mu.subject_id, mu.hadm_id, mu.stay_id,
         ie.los AS icu_los,
         h.hospital_expire_flag
  FROM most_unstable mu
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON mu.stay_id = ie.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` h ON ie.hadm_id = h.hadm_id
  WHERE mu.unstable_percentile <= 0.25  
)

SELECT 
  (SELECT percentile_rank_85 FROM percentile_calc LIMIT 1) AS percentile_of_85,
  AVG(icu_los_mortality.icu_los) AS avg_icu_los,
  AVG(icu_los_mortality.hospital_expire_flag) AS hospital_mortality_rate
FROM icu_los_mortality;