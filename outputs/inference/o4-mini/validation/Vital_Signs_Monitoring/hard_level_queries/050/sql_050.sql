WITH
  -- 1. Female ICU stays age 52–62
  icu_cohort AS (
    SELECT
      icu.subject_id,
      icu.hadm_id,
      icu.stay_id,
      icu.intime,
      icu.outtime,
      icu.los,
      p.anchor_age,
      a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON icu.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON icu.subject_id = a.subject_id
     AND icu.hadm_id    = a.hadm_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 52 AND 62
  ),

  -- 2. Identify RRT (dialysis) stays via procedureevents + d_items
  rrt_stays AS (
    SELECT DISTINCT
      pe.stay_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON pe.itemid = di.itemid
    WHERE LOWER(di.label) LIKE '%dialysis%'
  ),

  -- 3. First-72h instability scores 
  --    Replace with the correct project.dataset location of your score table or view
  first72_scores AS (
    SELECT
      stay_id,
      score
    FROM `your_project.your_dataset.vital_instability_first72h`
  ),

  -- 4. Filter to cohort + RRT + bring in LOS & mortality
  filtered AS (
    SELECT
      f.stay_id,
      f.score,
      icu.los,
      icu.hospital_expire_flag
    FROM first72_scores AS f
    JOIN icu_cohort AS icu
      ON f.stay_id = icu.stay_id
    JOIN rrt_stays AS r
      ON f.stay_id = r.stay_id
  ),

  -- 5. Percentile of score = 65
  pct65 AS (
    SELECT
      100.0 * CUME_DIST() OVER (ORDER BY score) AS percentile_for_65
    FROM filtered
    WHERE score = 65
    LIMIT 1  -- in case multiple observations at exactly 65
  ),

  -- 6. Stats for the top decile (PERCENT_RANK() >= 0.9)
  ranked AS (
    SELECT
      *,
      PERCENT_RANK() OVER (ORDER BY score) AS pr
    FROM filtered
  ),
  top_decile_stats AS (
    SELECT
      AVG(los) AS mean_icu_los,
      100.0 * AVG(IF(hospital_expire_flag = 1, 1.0, 0.0)) AS mortality_pct
    FROM ranked
    WHERE pr >= 0.9
  )

-- 7. Final output
SELECT
  p.percentile_for_65       AS percentile_of_65,
  t.mean_icu_los            AS top_decile_mean_los,
  t.mortality_pct           AS top_decile_mortality_pct
FROM pct65 AS p
CROSS JOIN top_decile_stats AS t;