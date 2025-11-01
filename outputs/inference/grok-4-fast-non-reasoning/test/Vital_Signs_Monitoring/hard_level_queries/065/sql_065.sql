WITH cohort AS (
  -- Base cohort: males 70-80 with ICU stay
  SELECT DISTINCT 
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.los,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 70 AND 80
),

rrt_cohort AS (
  -- Flag stays with RRT (itemids 225798-225811 in inputevents)
  SELECT 
    c.*,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
      INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON ie.subject_id = i.subject_id
        AND ie.stay_id = i.stay_id
      WHERE ie.subject_id = c.subject_id
        AND ie.hadm_id = c.hadm_id
        AND ie.stay_id = c.stay_id
        AND ie.itemid BETWEEN 225798 AND 225811
        AND ie.starttime BETWEEN i.intime AND i.outtime  -- Within stay
        AND ie.amountuom IS NOT NULL  -- Valid entry
    ) THEN 1 ELSE 0 END AS has_rrt
  FROM cohort c
),

vitals_rrt AS (
  -- Extract hypotension and tachycardia from chartevents for RRT (first 48 hours)
  SELECT 
    rc.subject_id,
    rc.stay_id,
    rc.hadm_id,
    rc.los,
    rc.has_rrt,
    rc.anchor_age,
    -- Hypotension proxy: % of MAP readings <65
    SAFE_DIVIDE(
      SUM(CASE WHEN ce.itemid = 220052 AND ce.valuenum < 65 THEN 1 ELSE 0 END),
      COUNT(CASE WHEN ce.itemid = 220052 THEN 1 END)
    ) * 100 AS pct_hypotime,
    -- Tachycardia episodes: count of HR >120 readings
    SUM(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 120 THEN 1 ELSE 0 END) AS tach_episodes
  FROM rrt_cohort rc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON rc.stay_id = i.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON rc.subject_id = ce.subject_id
    AND rc.hadm_id = ce.hadm_id
    AND rc.stay_id = ce.stay_id
    AND ce.charttime BETWEEN i.intime AND i.outtime
    AND ce.charttime <= i.intime + INTERVAL 48 HOUR  -- Limit to 48 hours
    AND ce.valuenum IS NOT NULL
  WHERE rc.has_rrt = 1
  GROUP BY rc.subject_id, rc.stay_id, rc.hadm_id, rc.los, rc.has_rrt, rc.anchor_age
),

scores_rrt AS (
  -- Composite score: hypotension % + capped tachycardia contribution (0-100 scale)
  SELECT 
    *,
    COALESCE(pct_hypotime, 0) + LEAST(COALESCE(tach_episodes, 0), 50) AS instability_score
  FROM vitals_rrt
),

percentile_cte AS (
  -- 90th percentile for RRT cohort
  SELECT 
    PERCENTILE_CONT(instability_score, 0.9) OVER() AS p90_score
  FROM scores_rrt
),

top_decile_rrt AS (
  -- Top decile RRT stays
  SELECT s.*
  FROM scores_rrt s
  CROSS JOIN percentile_cte p
  WHERE s.instability_score >= p.p90_score
),

vitals_non_rrt AS (
  -- Mirror vitals for non-RRT (first 48 hours)
  SELECT 
    rc.subject_id,
    rc.stay_id,
    rc.hadm_id,
    rc.los,
    rc.has_rrt,
    rc.anchor_age,
    SAFE_DIVIDE(
      SUM(CASE WHEN ce.itemid = 220052 AND ce.valuenum < 65 THEN 1 ELSE 0 END),
      COUNT(CASE WHEN ce.itemid = 220052 THEN 1 END)
    ) * 100 AS pct_hypotime,
    SUM(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 120 THEN 1 ELSE 0 END) AS tach_episodes
  FROM rrt_cohort rc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON rc.stay_id = i.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON rc.subject_id = ce.subject_id
    AND rc.hadm_id = ce.hadm_id
    AND rc.stay_id = ce.stay_id
    AND ce.charttime BETWEEN i.intime AND i.outtime
    AND ce.charttime <= i.intime + INTERVAL 48 HOUR  -- Limit to 48 hours
    AND ce.valuenum IS NOT NULL
  WHERE rc.has_rrt = 0
  GROUP BY rc.subject_id, rc.stay_id, rc.hadm_id, rc.los, rc.has_rrt, rc.anchor_age
),

-- Compute aggregates for top decile RRT with mortality
top_decile_agg AS (
  SELECT 
    'Top Decile RRT' AS group_label,
    ROUND(AVG(pct_hypotime), 2) AS avg_pct_hypotime,
    ROUND(AVG(tach_episodes), 2) AS avg_tach_episodes,
    ROUND(AVG(los), 2) AS avg_icu_los,
    ROUND(AVG(a.hospital_expire_flag) * 100, 2) AS mortality_pct,
    COUNT(*) AS n_patients
  FROM top_decile_rrt td
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON td.hadm_id = a.hadm_id
),

-- Compute aggregates for non-RRT with mortality
non_rrt_agg AS (
  SELECT 
    'Non-RRT' AS group_label,
    ROUND(AVG(pct_hypotime), 2) AS avg_pct_hypotime,
    ROUND(AVG(tach_episodes), 2) AS avg_tach_episodes,
    ROUND(AVG(los), 2) AS avg_icu_los,
    ROUND(AVG(a.hospital_expire_flag) * 100, 2) AS mortality_pct,
    COUNT(*) AS n_patients
  FROM vitals_non_rrt vn
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON vn.hadm_id = a.hadm_id
)

-- Final outputs: 90th percentile score
SELECT 
  '90th Percentile Instability Score (RRT Cohort)' AS metric,
  ROUND(p90_score, 2) AS value
FROM percentile_cte

-- Final outputs: Comparison table (hypotension, tachycardia, ICU LOS, mortality)
SELECT * FROM top_decile_agg
UNION ALL
SELECT * FROM non_rrt_agg;