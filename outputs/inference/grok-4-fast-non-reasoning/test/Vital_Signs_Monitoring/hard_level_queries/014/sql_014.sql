WITH eligible_stays_raw AS (
  -- Compute row number for first ICU stay
  SELECT 
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag,
    p.anchor_age,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
    AND i.los > 0
),
eligible_stays AS (
  -- Filter to first stay only
  SELECT *
  FROM eligible_stays_raw
  WHERE rn = 1
),
rrt_stays AS (
  -- Filter for stays with RRT (using EXISTS for any CRRT event)
  SELECT 
    es.*
  FROM eligible_stays es
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    WHERE pe.subject_id = es.subject_id
      AND pe.hadm_id = es.hadm_id
      AND pe.stay_id = es.stay_id
      AND pe.itemid = 225807  -- CVVHDF/CVVH; expand with others from d_items (e.g., 225816 for hemodialysis)
      AND pe.starttime BETWEEN es.intime AND es.outtime
  )
),
instability_scores AS (
  -- Placeholder: Assume instability_score derived per stay (e.g., MAX in first 72h from chartevents/labevents).
  -- In practice, join chartevents/labevents, filter charttime <= DATETIME_ADD(intime, INTERVAL 72 HOUR),
  -- compute score (e.g., weighted sum of abnormal vitals/labs), then MAX per stay.
  -- For demo, use a dummy score; replace with actual aggregation.
  SELECT 
    r.stay_id,
    r.subject_id,
    r.intime,
    -- Dummy score for illustration; replace with real derivation, e.g.:
    -- (SELECT MAX(CASE WHEN c.itemid IN (vital_itemids) AND c.valuenum > threshold THEN 1 ELSE 0 END)
    --  FROM chartevents c WHERE c.charttime <= DATETIME_ADD(r.intime, INTERVAL 72 HOUR) AND ... ) AS instability_score
    MOD(ABS(FARM_FINGERPRINT(r.subject_id)), 100) + 1 AS instability_score  -- Dummy 1-100 range
  FROM rrt_stays r
),
cohort_stats AS (
  -- Percentile for instability score of 85 in first 72h (using max score)
  SELECT 
    AVG(PERCENT_RANK() OVER (ORDER BY instability_score)) AS percentile_for_85
  FROM instability_scores
  WHERE instability_score = 85  -- Specific case; if no exact, use closest or filter cohort
),
quartile_stats AS (
  -- Most unstable quartile (top 25% by score)
  SELECT 
    NTILE(4) OVER (ORDER BY iscore.instability_score DESC) AS quartile,
    AVG(rs.los) AS avg_icu_los_days,
    AVG(rs.hospital_expire_flag * 1.0) AS hospital_mortality_rate
  FROM instability_scores iscore
  INNER JOIN rrt_stays rs
    ON iscore.stay_id = rs.stay_id
  GROUP BY quartile
  HAVING quartile = 1  -- Most unstable (highest scores)
)
SELECT 
  -- Part 1: Percentile for score 85
  (SELECT percentile_for_85 FROM cohort_stats) AS percentile_for_85,
  -- Part 2: Quartile stats
  (SELECT avg_icu_los_days FROM quartile_stats WHERE quartile = 1) AS most_unstable_quartile_icu_los,
  (SELECT hospital_mortality_rate FROM quartile_stats WHERE quartile = 1) AS most_unstable_quartile_mortality;