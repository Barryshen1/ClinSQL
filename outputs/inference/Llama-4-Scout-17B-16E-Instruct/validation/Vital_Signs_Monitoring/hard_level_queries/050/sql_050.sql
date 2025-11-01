WITH 
-- Filter and prepare patient data
patients_filtered AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age, 
    icu.stay_id, 
    icu.intime, 
    icu.outtime,
    icu.los,
    h.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu 
  ON 
    p.subject_id = icu.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` h
  ON 
    p.subject_id = h.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 52 AND 62
),

-- Identify patients who received renal replacement therapy
rrt_patients AS (
  SELECT 
    subject_id, 
    hadm_id, 
    stay_id
  FROM 
    `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE 
    itemid = 227000  -- Assuming this is the itemid for RRT
),

-- Join patients with RRT and calculate instability score (example, actual calculation may vary)
instability_scores AS (
  SELECT 
    p.subject_id, 
    p.stay_id, 
    -- Example calculation, replace with actual formula
    AVG(CASE 
          WHEN ce.itemid = 220050 AND valuenum > 100 THEN 1 
          ELSE 0 
        END) AS instability_score
  FROM 
    patients_filtered p
  JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce 
  ON 
    p.stay_id = ce.stay_id
  WHERE 
    ce.charttime BETWEEN p.intime AND TIMESTAMP_ADD(p.intime, INTERVAL 72 HOUR)
  GROUP BY 
    p.subject_id, 
    p.stay_id
),

-- Calculate percentile
percentile_65 AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100) AS quantiles
  FROM 
    instability_scores
),

top_decile_stats AS (
  SELECT 
    AVG(los) AS mean_icu_los,
    SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate
  FROM 
    patients_filtered p
  JOIN 
    instability_scores i 
  ON 
    p.subject_id = i.subject_id AND p.stay_id = i.stay_id
  WHERE 
    i.instability_score >= (SELECT quantiles[91] FROM percentile_65)
)

-- Final query
SELECT 
  (SELECT quantiles[50] FROM percentile_65) AS percentile_50,
  (SELECT quantiles[65] FROM percentile_65) AS percentile_65,
  (SELECT mean_icu_los FROM top_decile_stats) AS mean_icu_los,
  (SELECT mortality_rate FROM top_decile_stats) AS mortality_rate;