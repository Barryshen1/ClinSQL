WITH cohort AS (
  SELECT p.subject_id, ie.hadm_id, ie.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON p.subject_id = ie.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 75 AND 85
),
ventilated AS (
  SELECT DISTINCT c.stay_id
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON c.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE di.label LIKE '%Invasive Vent%'
),
instability_score AS (
  SELECT v.stay_id, 
         AVG(CASE WHEN di.label LIKE '%Heart Rate%' THEN ce.valuenum END) AS avg_hr,
         AVG(CASE WHEN di.label LIKE '%Systolic Blood Pressure%' THEN ce.valuenum END) AS avg_sbp
  FROM ventilated v
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON v.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE ce.charttime BETWEEN (SELECT intime FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE stay_id = v.stay_id)
                      AND TIMESTAMP_ADD((SELECT intime FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE stay_id = v.stay_id), INTERVAL 48 HOUR)
  GROUP BY v.stay_id
),
composite_score AS (
  SELECT stay_id, 
         (avg_hr + avg_sbp) AS composite_score  
  FROM instability_score
),
score_percentile AS (
  SELECT PERCENTILE_CONT(composite_score, 0.9) AS score_90th_percentile
  FROM composite_score
),
top_25_percent AS (
  SELECT stay_id
  FROM composite_score
  WHERE composite_score >= (SELECT PERCENTILE_CONT(composite_score, 0.75) FROM composite_score)
),
final_stats AS (
  SELECT 
    ie.los,
    p.dod,
    ce.valuenum,
    di.label
  FROM top_25_percent t
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON t.stay_id = ie.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON ie.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON t.stay_id = ce.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE di.label LIKE '%Systolic Blood Pressure%' OR di.label LIKE '%Heart Rate%'
)
SELECT 
  (SELECT score_90th_percentile FROM score_percentile) AS score_90th_percentile,
  PERCENTILE_CONT(ie.los, 0.5) OVER () AS median_icu_los,
  AVG(CASE WHEN ie.los > 7 THEN 1 ELSE 0 END) AS prop_icu_los_gt_7,
  AVG(CASE WHEN p.dod IS NOT NULL THEN 1 ELSE 0 END) AS mortality,
  AVG(CASE WHEN di.label LIKE '%Systolic Blood Pressure%' AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS hypotension,
  AVG(CASE WHEN di.label LIKE '%Heart Rate%' AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia
FROM top_25_percent t
JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON t.stay_id = ie.stay_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON ie.subject_id = p.subject_id
LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON t.stay_id = ce.stay_id
LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
WHERE di.label LIKE '%Systolic Blood Pressure%' OR di.label LIKE '%Heart Rate%';