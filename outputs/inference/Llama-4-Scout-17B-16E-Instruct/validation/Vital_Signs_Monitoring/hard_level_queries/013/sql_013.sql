WITH 
-- Identify population of interest
population AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    icu.intime AS icu_intime,
    icu.outtime AS icu_outtime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON i.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON i.hadm_id = a.hadm_id
  JOIN 
    (SELECT 
       subject_id, 
       hadm_id, 
       MIN(intime) AS intime, 
       MAX(outtime) AS outtime
     FROM 
       `physionet-data.mimiciv_3_1_icu.icustays`
     GROUP BY 
       subject_id, 
       hadm_id) icu 
    ON i.subject_id = icu.subject_id AND i.hadm_id = icu.hadm_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admission_type = 'Trauma'
    AND i.first_careunit = i.last_careunit
),

-- Calculate vital-sign instability scores
vital_signs AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    itemid,
    value,
    valuenum
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE 
    itemid IN (220050,  -- Heart Rate
               220179,  -- Respiratory Rate
               220052)  -- Systolic Blood Pressure
),

-- Calculate instability scores
instability_scores_cte AS (
  SELECT 
    vs.subject_id,
    vs.hadm_id,
    vs.stay_id,
    COUNT(DISTINCT vs.charttime) AS num_measurements,
    AVG(CASE WHEN vs.itemid = 220050 THEN vs.valuenum ELSE NULL END) AS mean_heart_rate,
    AVG(CASE WHEN vs.itemid = 220179 THEN vs.valuenum ELSE NULL END) AS mean_respiratory_rate,
    AVG(CASE WHEN vs.itemid = 220052 THEN vs.valuenum ELSE NULL END) AS mean_systolic_blood_pressure
  FROM 
    vital_signs vs
  GROUP BY 
    vs.subject_id,
    vs.hadm_id,
    vs.stay_id
),

-- Calculate 24-h vital-sign instability scores
final_scores AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    (ABS(is_c.mean_heart_rate - 60) + 
     ABS(is_c.mean_respiratory_rate - 20) + 
     ABS(is_c.mean_systolic_blood_pressure - 120)) / 3 AS instability_score,
    TIMESTAMP_DIFF(p.icu_outtime, p.icu_intime, DAY) AS icu_los,
    CASE 
      WHEN p.deathtime IS NOT NULL THEN 1 
      ELSE 0 
    END AS mortality
  FROM 
    population p
  JOIN 
    instability_scores_cte is_c 
      ON p.subject_id = is_c.subject_id AND p.hadm_id = is_c.hadm_id AND p.stay_id = is_c.stay_id
),

-- Stratify scores into quartiles and report metrics
quartiles AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    instability_score,
    icu_los,
    mortality,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile
  FROM 
    final_scores
)

-- Report by quartile
SELECT 
  q.quartile,
  COUNT(*) AS count,
  AVG(q.instability_score) AS mean_score,
  AVG(q.icu_los) AS mean_icu_los,
  AVG(q.mortality) AS mortality
FROM 
  quartiles q
GROUP BY 
  q.quartile
ORDER BY 
  q.quartile;

-- For top decile
WITH ranked_scores AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    instability_score,
    icu_los,
    mortality,
    ROW_NUMBER() OVER (ORDER BY instability_score DESC) AS row_num
  FROM 
    final_scores
),
top_decile AS (
  SELECT 
    ce.itemid,
    ce.valuenum,
    rs.row_num
  FROM 
    ranked_scores rs
  JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce 
      ON rs.subject_id = ce.subject_id AND rs.hadm_id = ce.hadm_id AND rs.stay_id = ce.stay_id
  WHERE 
    rs.row_num <= 10
)
SELECT 
  COUNT(*) AS count,
  AVG(CASE 
          WHEN itemid = 220050 AND valuenum > 100 THEN 1 
          ELSE 0 
        END) AS mean_tachycardia_episodes,
  AVG(CASE 
          WHEN itemid = 220052 AND valuenum < 90 THEN 1 
          ELSE 0 
        END) AS mean_hypotension_episodes,
  AVG(CASE 
          WHEN itemid = 220179 AND valuenum > 30 THEN 1 
          ELSE 0 
        END) AS mean_tachypnea_episodes
FROM 
  top_decile;