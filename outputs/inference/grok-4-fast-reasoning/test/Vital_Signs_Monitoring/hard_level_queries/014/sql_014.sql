WITH rrt_itemids AS (
  -- Common itemids for RRT (CRRT fluids, dialysate, anticoagulants)
  SELECT itemid FROM UNNEST([225798, 225826, 220615, 226089, 227017, 225834, 225916, 3004242, 3004243, 3004244, 3004245, 3004246]) AS itemid
),
cohort AS (
  -- Base cohort: male, 88-98yo, first ICU stay
  SELECT 
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN (
    -- First stay per subject
    SELECT subject_id, ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) first_stay ON i.subject_id = first_stay.subject_id AND first_stay.rn = 1
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
),
rrt_cohort AS (
  -- Filter cohort to those on RRT during stay
  SELECT 
    c.*
  FROM cohort c
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
    INNER JOIN rrt_itemids ri ON ie.itemid = ri.itemid
    WHERE ie.subject_id = c.subject_id
      AND ie.hadm_id = c.hadm_id
      AND ie.stay_id = c.stay_id
      AND ie.starttime BETWEEN c.intime AND c.outtime  -- During stay
  )
),
patient_scores AS (
  -- Placeholder CTE for instability_score (max in first 72h; in practice, derive from chartevents/labevents/procedureevents)
  -- Example structure: aggregate MAX(derived_score) WHERE charttime BETWEEN intime AND TIMESTAMP_ADD(intime, INTERVAL 72 HOUR)
  SELECT 
    rc.subject_id,
    rc.stay_id,
    rc.hadm_id,
    rc.los,
    rc.hospital_expire_flag,
    -- Placeholder: replace with actual derivation, e.g.,
    -- (CASE WHEN /* SOFA-like calc */ THEN score ELSE 0 END) as instability_score
    -- For demo, use a fixed range 0-100; in reality, compute per stay
    RAND() * 100 AS instability_score  -- Dummy; replace with real aggregation
  FROM rrt_cohort rc
  -- In practice, LEFT JOIN relevant events and aggregate:
  -- LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ... AND ce.charttime BETWEEN rc.intime AND TIMESTAMP_ADD(rc.intime, INTERVAL 72 HOUR)
  -- GROUP BY rc.subject_id, rc.stay_id, ... HAVING COUNT(*) > 0
)
-- Compute percentile for score=85 and stats for most unstable quartile (top 25% by descending score)
SELECT 
  -- Percentile: % of stays with score <=85
  (COUNTIF(instability_score <= 85) * 100.0 / COUNT(*)) AS percentile_for_85,
  -- Most unstable quartile stats
  AVG(CASE WHEN quartile = 1 THEN los END) AS avg_icu_los_most_unstable_quartile,
  AVG(CASE WHEN quartile = 1 THEN hospital_expire_flag END) AS hospital_mortality_most_unstable_quartile
FROM (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY instability_score DESC) AS quartile  -- 1 = most unstable (highest scores)
  FROM patient_scores
);