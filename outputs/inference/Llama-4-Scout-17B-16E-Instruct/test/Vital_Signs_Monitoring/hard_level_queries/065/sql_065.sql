WITH 
-- Identify RRT patients
rrt_patients AS (
  SELECT DISTINCT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id
  FROM 
    `physionet-data.mimiciv_3_1_icu.inputevents` ie
  WHERE 
    ie.itemid IN (
      221050,  -- CVVHD
      221051,  -- CVVH
      221052   -- CVVHD with dialysis
    )
),

-- Calculate vital instability scores
vital_scores AS (
  SELECT 
    ce.subject_id, 
    ce.hadm_id, 
    ce.stay_id, 
    ce.charttime,
    CASE 
      WHEN ce.itemid = 220050 AND valuenum < 65 THEN 1  -- Hypotension (MAP < 65)
      ELSE 0 
    END AS hypotension,
    CASE 
      WHEN ce.itemid = 220179 AND valuenum > 100 THEN 1  -- Tachycardia (HR > 100)
      ELSE 0 
    END AS tachycardia
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE 
    ce.itemid IN (220050, 220179)  -- MAP and Heart Rate
),

-- Aggregate instability scores over 48 hours
instability_scores AS (
  SELECT 
    vs.subject_id, 
    vs.hadm_id, 
    vs.stay_id,
    SUM(vs.hypotension) + SUM(vs.tachycardia) AS instability_score
  FROM 
    vital_scores vs
  GROUP BY 
    vs.subject_id, 
    vs.hadm_id, 
    vs.stay_id
),

-- Identify target population and RRT status
target_population AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age,
    COALESCE(rrt.subject_id, 0) AS rrt_status
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  LEFT JOIN 
    rrt_patients rrt ON p.subject_id = rrt.subject_id
  WHERE 
    p.gender = 'M' AND 
    p.anchor_age BETWEEN 70 AND 80
),

-- Join target population with ICU stays and instability scores
population_scores AS (
  SELECT 
    tp.subject_id,
    tp.rrt_status,
    isc.instability_score
  FROM 
    target_population tp
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu ON tp.subject_id = icu.subject_id
  JOIN 
    instability_scores isc ON icu.stay_id = isc.stay_id
  WHERE 
    tp.rrt_status = 1
)

-- Main query to calculate 90th percentile
SELECT 
  APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS percentile_90
FROM 
  population_scores;