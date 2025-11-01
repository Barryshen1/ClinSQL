WITH 
-- Filter female patients aged 49-59 and calculate composite vital instability score
eligible_patients_score AS (
  WITH 
  vital_signs AS (
    SELECT p.subject_id, icu.stay_id, icu.intime,
           MAX(CASE WHEN di.label = 'Heart Rate' THEN ce.valuenum END) AS max_hr,
           MIN(CASE WHEN di.label = 'Heart Rate' THEN ce.valuenum END) AS min_hr,
           MAX(CASE WHEN di.label = 'Systolic Blood Pressure' THEN ce.valuenum END) AS max_sbp,
           MIN(CASE WHEN di.label = 'Systolic Blood Pressure' THEN ce.valuenum END) AS min_sbp,
           MAX(CASE WHEN di.label = 'Respiratory Rate' THEN ce.valuenum END) AS max_rr,
           MIN(CASE WHEN di.label = 'Respiratory Rate' THEN ce.valuenum END) AS min_rr
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON p.subject_id = icu.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON icu.stay_id = ce.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
    WHERE p.gender = 'F' AND p.anchor_age BETWEEN 49 AND 59
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
    AND di.label IN ('Heart Rate', 'Systolic Blood Pressure', 'Respiratory Rate')
    GROUP BY p.subject_id, icu.stay_id, icu.intime
  )
  SELECT subject_id, stay_id, intime,
         (max_hr - min_hr) + (max_sbp - min_sbp) + (max_rr - min_rr) AS score
  FROM vital_signs
),

-- Calculate ICU length of stay and hospital mortality
icu_los_mortality AS (
  SELECT icu.stay_id, 
         DATETIME_DIFF(icu.outtime, icu.intime, DAY) AS icu_los_days,
         CASE WHEN adm.deathtime IS NOT NULL THEN 1 ELSE 0 END AS hospital_mortality
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON icu.hadm_id = adm.hadm_id
),

-- Calculate percentile and top decile threshold
percentiles AS (
  SELECT 
    PERCENTILE_CONT(score, 0.5) OVER () AS median_score,
    PERCENTILE_CONT(score, 0.9) AS top_decile_threshold
  FROM eligible_patients_score
),

score_stats AS (
  SELECT 
    COUNTIF(score <= 70) / COUNT(*) AS percentile_70,
    ANY_VALUE(top_decile_threshold) AS top_decile_threshold
  FROM eligible_patients_score
  CROSS JOIN (SELECT top_decile_threshold FROM percentiles LIMIT 1) p
)

-- Main query
SELECT 
  s.percentile_70,
  AVG(CASE WHEN eps.score >= s.top_decile_threshold THEN ilm.icu_los_days END) AS mean_icu_los_days_top_decile,
  AVG(CASE WHEN eps.score >= s.top_decile_threshold THEN ilm.hospital_mortality END) * 100 AS hospital_mortality_percent_top_decile
FROM icu_los_mortality ilm
JOIN eligible_patients_score eps ON ilm.stay_id = eps.stay_id
CROSS JOIN score_stats s;