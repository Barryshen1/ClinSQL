WITH
-- 1) map relevant itemids to physiological types using d_items (ICU module)
vital_item_map AS (
  SELECT itemid,
    label,
    CASE
      WHEN LOWER(label) LIKE '%mean blood pressure%' OR LOWER(label) LIKE '%mean bp%' OR LOWER(label) LIKE '%arterial bp mean%' OR LOWER(label) LIKE '%invasive mean%' OR LOWER(label) LIKE '%map%' THEN 'map'
      WHEN (LOWER(label) LIKE '%heart rate%' OR LOWER(label) LIKE '%hr%' OR LOWER(label) LIKE '%pulse%') THEN 'hr'
      WHEN (LOWER(label) LIKE '%respiratory rate%' OR LOWER(label) LIKE '%resp rate%' OR LOWER(label) LIKE '%rr%') THEN 'rr'
      WHEN (LOWER(label) LIKE '%spo2%' OR LOWER(label) LIKE '%o2 saturation%' OR LOWER(label) LIKE '%oxygen saturation%') THEN 'spo2'
      ELSE NULL
    END AS vital_type
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean blood pressure%' OR LOWER(label) LIKE '%mean bp%' OR LOWER(label) LIKE '%arterial bp mean%' OR LOWER(label) LIKE '%invasive mean%' OR LOWER(label) LIKE '%map%'
     OR LOWER(label) LIKE '%heart rate%' OR LOWER(label) LIKE '%pulse%'
     OR LOWER(label) LIKE '%respiratory rate%' OR LOWER(label) LIKE '%resp rate%' OR LOWER(label) LIKE '%rr%'
     OR LOWER(label) LIKE '%spo2%' OR LOWER(label) LIKE '%o2 saturation%' OR LOWER(label) LIKE '%oxygen saturation%'
),
-- 2) cohort: ICU stays for female patients age 43-53 with acute respiratory failure diagnosis on the same hadm_id
cohort_stays AS (
  SELECT DISTINCT s.subject_id, s.hadm_id, s.stay_id, s.intime, s.outtime, s.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON s.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '518%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'J96%')
    )
),
-- 3) extract vitals in first 48 hours for the cohort (and tag abnormal flags)
cohort_vitals48 AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    vim.vital_type,
    c.valuenum,
    -- abnormal flags using chosen thresholds
    CASE WHEN vim.vital_type = 'map'  AND c.valuenum IS NOT NULL AND c.valuenum < 65 THEN 1 ELSE 0 END AS is_map_low,
    CASE WHEN vim.vital_type = 'hr'   AND c.valuenum IS NOT NULL AND c.valuenum > 100 THEN 1 ELSE 0 END AS is_hr_tachy,
    CASE WHEN vim.vital_type = 'rr'   AND c.valuenum IS NOT NULL AND c.valuenum > 25 THEN 1 ELSE 0 END AS is_rr_high,
    CASE WHEN vim.vital_type = 'spo2' AND c.valuenum IS NOT NULL AND c.valuenum < 90 THEN 1 ELSE 0 END AS is_spo2_low
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN vital_item_map vim
    ON c.itemid = vim.itemid
  JOIN cohort_stays s
    ON c.stay_id = s.stay_id
  WHERE c.charttime >= s.intime
    AND c.charttime <= TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
    AND c.valuenum IS NOT NULL
),
-- 4) per-stay instability index for cohort
cohort_index AS (
  SELECT
    stay_id,
    COUNT(1) AS total_measurements,
    SUM(is_map_low + is_hr_tachy + is_rr_high + is_spo2_low) AS total_abnormal_measurements,
    SAFE_DIVIDE(SUM(is_map_low + is_hr_tachy + is_rr_high + is_spo2_low), COUNT(1)) AS vital_instability_index
  FROM cohort_vitals48
  GROUP BY stay_id
  HAVING COUNT(1) > 0
),
-- 5) compute 95th percentile and 75th percentile (top quartile threshold) of index within cohort
cohort_index_percentiles AS (
  SELECT
    APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(95)] AS p95_index,
    APPROX_QUANTILES(vital_instability_index, 4)[OFFSET(3)] AS p75_index
  FROM cohort_index
),
-- 6) identify top-quartile stays in the cohort
cohort_top_quartile AS (
  SELECT ci.stay_id, ci.vital_instability_index
  FROM cohort_index ci
  JOIN cohort_index_percentiles p ON TRUE
  WHERE ci.vital_instability_index >= p.p75_index
),
-- 7) For episodes we need MAP and HR event streams within first 48h for both cohort and general ICU population.
-- Map & HR events for cohort (to count episodes)
cohort_map_hr_events AS (
  SELECT
    c.stay_id,
    c.charttime,
    vim.vital_type,
    c.valuenum,
    CASE WHEN vim.vital_type = 'map'  AND c.valuenum < 65 THEN 1 ELSE 0 END AS map_low,
    CASE WHEN vim.vital_type = 'hr'   AND c.valuenum > 100 THEN 1 ELSE 0 END AS hr_tachy
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN vital_item_map vim ON c.itemid = vim.itemid
  JOIN cohort_stays s ON c.stay_id = s.stay_id
  WHERE c.charttime >= s.intime
    AND c.charttime <= TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
    AND vim.vital_type IN ('map', 'hr')
    AND c.valuenum IS NOT NULL
),
-- 8) episode starts for cohort (map & hr)
cohort_episode_starts AS (
  SELECT
    stay_id,
    SUM(CASE WHEN map_low = 1 AND (prev_map_low IS NULL OR prev_map_low = 0) THEN 1 ELSE 0 END) AS map_episode_starts,
    SUM(CASE WHEN hr_tachy = 1 AND (prev_hr_tachy IS NULL OR prev_hr_tachy = 0) THEN 1 ELSE 0 END) AS hr_episode_starts
  FROM (
    SELECT
      stay_id,
      charttime,
      map_low,
      hr_tachy,
      LAG(map_low) OVER (PARTITION BY stay_id ORDER BY charttime) AS prev_map_low,
      LAG(hr_tachy)  OVER (PARTITION BY stay_id ORDER BY charttime) AS prev_hr_tachy
    FROM cohort_map_hr_events
  )
  GROUP BY stay_id
),
-- 9) Bring together cohort top quartile metrics: episodes, LOS, mortality
cohort_top_metrics AS (
  SELECT
    'cohort_top_quartile' AS cohort_group,
    COUNT(DISTINCT tq.stay_id) AS n_stays,
    -- mean episodes per stay (map & hr): join episode starts, if no episodes table row then zero
    AVG(IFNULL(e.map_episode_starts, 0)) AS mean_map_hypotension_episodes_per_stay,
    AVG(IFNULL(e.hr_episode_starts, 0))  AS mean_hr_tachycardia_episodes_per_stay,
    AVG(s.los) AS mean_icu_los_days,
    AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS hospital_mortality_rate
  FROM cohort_top_quartile tq
  LEFT JOIN cohort_episode_starts e ON tq.stay_id = e.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` s ON tq.stay_id = s.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON s.hadm_id = a.hadm_id
),
-- 10) Now compute general ICU population metrics using the same definitions (first 48h from each icu stay)
-- All adult ICU stays with at least one MAP or HR measurement in first 48h
all_icustays_with_measurements AS (
  SELECT DISTINCT s.subject_id, s.hadm_id, s.stay_id, s.intime, s.outtime, s.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON s.stay_id = c.stay_id
  JOIN vital_item_map vim
    ON c.itemid = vim.itemid
  WHERE vim.vital_type IN ('map','hr') -- require at least one MAP or HR measurement to be included
    AND c.charttime >= s.intime
    AND c.charttime <= TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
    AND c.valuenum IS NOT NULL
),
-- 11) map & hr events for general population
all_map_hr_events AS (
  SELECT
    c.stay_id,
    c.charttime,
    vim.vital_type,
    c.valuenum,
    CASE WHEN vim.vital_type = 'map' AND c.valuenum < 65 THEN 1 ELSE 0 END AS map_low,
    CASE WHEN vim.vital_type = 'hr'  AND c.valuenum > 100 THEN 1 ELSE 0 END AS hr_tachy
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN vital_item_map vim ON c.itemid = vim.itemid
  JOIN all_icustays_with_measurements s ON c.stay_id = s.stay_id
  WHERE c.charttime >= s.intime
    AND c.charttime <= TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
    AND vim.vital_type IN ('map', 'hr')
    AND c.valuenum IS NOT NULL
),
-- 12) episode starts for general population
all_episode_starts AS (
  SELECT
    stay_id,
    SUM(CASE WHEN map_low = 1 AND (prev_map_low IS NULL OR prev_map_low = 0) THEN 1 ELSE 0 END) AS map_episode_starts,
    SUM(CASE WHEN hr_tachy = 1 AND (prev_hr_tachy IS NULL OR prev_hr_tachy = 0) THEN 1 ELSE 0 END) AS hr_episode_starts
  FROM (
    SELECT
      stay_id,
      charttime,
      map_low,
      hr_tachy,
      LAG(map_low) OVER (PARTITION BY stay_id ORDER BY charttime) AS prev_map_low,
      LAG(hr_tachy)  OVER (PARTITION BY stay_id ORDER BY charttime) AS prev_hr_tachy
    FROM all_map_hr_events
  )
  GROUP BY stay_id
),
-- 13) metrics for general ICU population
general_icu_metrics AS (
  SELECT
    'general_icu_population' AS cohort_group,
    COUNT(DISTINCT s.stay_id) AS n_stays,
    AVG(IFNULL(e.map_episode_starts, 0)) AS mean_map_hypotension_episodes_per_stay,
    AVG(IFNULL(e.hr_episode_starts, 0))  AS mean_hr_tachycardia_episodes_per_stay,
    AVG(s.los) AS mean_icu_los_days,
    AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS hospital_mortality_rate
  FROM all_icustays_with_measurements s
  LEFT JOIN all_episode_starts e ON s.stay_id = e.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON s.hadm_id = a.hadm_id
)
-- Final outputs: 95th percentile of vital instability index for the cohort, then comparison rows
SELECT
  'cohort_vital_index_p95' AS metric,
  CAST(p.p95_index AS STRING) AS value,
  NULL AS n_stays,
  NULL AS mean_map_hypotension_episodes_per_stay,
  NULL AS mean_hr_tachycardia_episodes_per_stay,
  NULL AS mean_icu_los_days,
  NULL AS hospital_mortality_rate
FROM cohort_index_percentiles p

UNION ALL

SELECT
  cohort_group AS metric,
  NULL AS value,
  CAST(n_stays AS STRING),
  CAST(mean_map_hypotension_episodes_per_stay AS STRING),
  CAST(mean_hr_tachycardia_episodes_per_stay AS STRING),
  CAST(mean_icu_los_days AS STRING),
  CAST(hospital_mortality_rate AS STRING)
FROM (
  SELECT * FROM cohort_top_metrics
  UNION ALL
  SELECT * FROM general_icu_metrics
)
ORDER BY metric;