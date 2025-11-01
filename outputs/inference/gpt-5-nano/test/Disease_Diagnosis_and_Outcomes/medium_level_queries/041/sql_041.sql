WITH
  -- 1) Base population: female 50-60 with a hospital stay
  base_population AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.deathtime,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS LOS_DAYS
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 50 AND 60
      AND a.dischtime IS NOT NULL
  ),

  -- 2) Sepsis cases excluding septic shock
  sepsis_admissions AS (
    SELECT bp.subject_id, bp.hadm_id, bp.admittime, bp.dischtime, bp.deathtime, bp.LOS_DAYS
    FROM base_population AS bp
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      ON bp.subject_id = di.subject_id AND bp.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE (di.icd_code LIKE 'A40%' OR di.icd_code LIKE 'A41%' OR dd.long_title LIKE '%sepsis%')
      -- Exclude septic shock
      AND NOT EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd2
          ON di2.icd_code = dd2.icd_code AND di2.icd_version = dd2.icd_version
        WHERE di2.subject_id = bp.subject_id
          AND di2.hadm_id = bp.hadm_id
          AND di2.icd_code = 'R57.2'
      )
  ),

  -- 3) Group-level statistics by LOS category
  group_stats AS (
    SELECT
      CASE WHEN LOS_DAYS <= 7 THEN '≤7' ELSE '>7' END AS los_group,
      COUNT(*) AS cohort_size,
      SUM(CASE WHEN deathtime IS NOT NULL THEN 1 ELSE 0 END) AS deaths,
      SAFE_DIVIDE(SUM(CASE WHEN deathtime IS NOT NULL THEN 1 ELSE 0 END), COUNT(*)) * 100 AS mortality_pct,
      MEDIAN(TIMESTAMP_DIFF(deathtime, admittime, SECOND) / 3600.0) AS median_time_to_death_hours
    FROM sepsis_admissions
    GROUP BY los_group
  ),

  -- 4) Differences/ratios between LOS groups
  diff AS (
    SELECT
      MAX(CASE WHEN los_group = '≤7' THEN mortality_pct END) AS mor_le7,
      MAX(CASE WHEN los_group = '>7' THEN mortality_pct END) AS mor_gt7,
      MAX(CASE WHEN los_group = '≤7' THEN median_time_to_death_hours END) AS median_le7,
      MAX(CASE WHEN los_group = '>7' THEN median_time_to_death_hours END) AS median_gt7
    FROM group_stats
  )

-- 5) Present results: include mortality, medians, and differences
SELECT label, value
FROM (
  -- Mortality by LOS group
  SELECT CAST('LOS ≤7 days mortality (%)' AS STRING) AS label, mor_le7 AS value FROM diff
  UNION ALL
  SELECT CAST('LOS >7 days mortality (%)',) AS label, mor_gt7 AS value FROM diff
  UNION ALL
  -- Absolute/Relative mortality differences
  SELECT CAST('Absolute difference in mortality (≤7 - >7)' AS STRING), mor_le7 - mor_gt7 FROM diff
  UNION ALL
  SELECT CAST('Relative difference in mortality (≤7 / >7)' AS STRING), CASE WHEN mor_gt7 = 0 THEN NULL ELSE mor_le7 / mor_gt7 END FROM diff
  UNION ALL
  -- Median time-to-death by LOS group
  SELECT CAST('Median time-to-death hours (LOS ≤7)' AS STRING), median_le7 FROM diff
  UNION ALL
  SELECT CAST('Median time-to-death hours (LOS >7)' AS STRING), median_gt7 FROM diff
  UNION ALL
  -- Difference in medians
  SELECT CAST('Difference in median time-to-death (≤7 - >7)' AS STRING), median_le7 - median_gt7 FROM diff
  UNION ALL
  SELECT CAST('Relative difference in median time-to-death (≤7 / >7)' AS STRING), CASE WHEN median_gt7 = 0 THEN NULL ELSE median_le7 / median_gt7 END FROM diff
) AS t;