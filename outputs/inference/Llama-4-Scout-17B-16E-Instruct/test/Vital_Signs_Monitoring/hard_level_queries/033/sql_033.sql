WITH 
-- Define population of interest
target_population AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    a.hadm_id,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON ic.hadm_id = a.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON ic.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
),

-- Assume instability score is derived from chartevents with a specific itemid
instability_scores AS (
  SELECT 
    subject_id,
    stay_id,
    charttime,
    valuenum AS instability_score
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE 
    itemid = 220050  -- Replace with actual itemid for instability score, e.g., 220050 for 'Instability Score'
    AND charttime BETWEEN TIMESTAMP(intime) AND TIMESTAMP(intime + INTERVAL 48 HOUR)
),

-- Merge instability scores with target population
scores_with_population AS (
  SELECT 
    tp.*,
    isc.instability_score
  FROM 
    target_population tp
  JOIN 
    instability_scores isc 
      ON tp.subject_id = isc.subject_id AND tp.stay_id = isc.stay_id
),

-- Rank instability scores
ranked_scores AS (
  SELECT 
    *,
    PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile
  FROM 
    scores_with_population
),

-- Identify most unstable decile
most_unstable_decile AS (
  SELECT 
    TIMESTAMP_DIFF(outtime, intime, HOUR) AS icu_los,
    hospital_expire_flag
  FROM 
    ranked_scores
  WHERE 
    percentile >= 0.9  -- Top 10%
)

-- Calculate percentile and outcomes
SELECT 
  APPROX_QUANTILES(instability_score, 100)[11] AS percentile_80_score,
  AVG(TIMESTAMP_DIFF(outtime, intime, HOUR)) AS avg_icu_los,
  SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate
FROM 
  scores_with_population;

-- To get ICU LOS and mortality for the most unstable decile
SELECT 
  'Most Unstable Decile' AS group_name,
  AVG(icu_los) AS avg_icu_los,
  SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate
FROM 
  most_unstable_decile;