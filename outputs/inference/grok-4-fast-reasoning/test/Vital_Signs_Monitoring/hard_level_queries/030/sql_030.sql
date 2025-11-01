WITH all_stays AS (
  -- All adult ICU stays with basics
  SELECT 
    icu.stay_id, icu.subject_id, icu.hadm_id, icu.intime, icu.outtime, icu.los, 
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat ON icu.subject_id = pat.subject_id
  WHERE pat.anchor_age >= 18
),
hypo_counts AS (
  -- Hypotension counts (MAP < 65) over entire stay for all stays
  SELECT 
    ce.stay_id, 
    COUNT(*) AS hypo_episodes
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN all_stays s ON ce.stay_id = s.stay_id
  WHERE ce.itemid = 220052  -- MAP
    AND ce.valuenum < 65
    AND ce.charttime >= s.intime
    AND ce.charttime <= s.outtime
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
),
tachy_counts AS (
  -- Tachycardia counts (HR > 100) over entire stay for all stays
  SELECT 
    ce.stay_id, 
    COUNT(*) AS tachy_episodes
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN all_stays s ON ce.stay_id = s.stay_id
  WHERE ce.itemid = 220045  -- HR
    AND ce.valuenum > 100
    AND ce.charttime >= s.intime
    AND ce.charttime <= s.outtime
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
),
all_with_vitals AS (
  -- All stays with hypo/tachy counts
  SELECT 
    s.*, 
    COALESCE(h.hypo_episodes, 0) AS hypo_episodes, 
    COALESCE(t.tachy_episodes, 0) AS tachy_episodes
  FROM all_stays s
  LEFT JOIN hypo_counts h ON s.stay_id = h.stay_id
  LEFT JOIN tachy_counts t ON s.stay_id = t.stay_id
),
cohort_stay_ids AS (
  -- Cohort: female, age 43-53, with acute resp failure dx
  SELECT DISTINCT 
    icu.stay_id, icu.subject_id, icu.hadm_id, icu.intime, icu.outtime, icu.los, 
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 43 AND 53
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.subject_id = icu.subject_id 
        AND diag.hadm_id = icu.hadm_id
        AND diag.icd_version = 10
        AND diag.icd_code LIKE 'J96%'
    )
),
unstable_first48 AS (
  -- Instability index: count abnormal HR/MAP in first 48h for cohort
  SELECT 
    ce.stay_id, 
    COUNT(*) AS instability_index
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN cohort_stay_ids c ON ce.stay_id = c.stay_id
  WHERE ce.itemid IN (220045, 220052)
    AND ce.charttime >= c.intime
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
    AND (
      (ce.itemid = 220045 AND ce.valuenum > 100) OR 
      (ce.itemid = 220052 AND ce.valuenum < 65)
    )
  GROUP BY ce.stay_id
),
cohort_full AS (
  -- Cohort with all metrics (vitals + index)
  SELECT 
    awv.*, 
    COALESCE(u.instability_index, 0) AS instability_index
  FROM all_with_vitals awv
  INNER JOIN cohort_stay_ids cs ON awv.stay_id = cs.stay_id
  LEFT JOIN unstable_first48 u ON awv.stay_id = u.stay_id
),
cohort_pcts AS (
  -- 95th and 75th percentiles of index
  SELECT 
    PERCENTILE_CONT(instability_index, 0.95) OVER() AS p95,
    PERCENTILE_CONT(instability_index, 0.75) OVER() AS p75
  FROM cohort_full
  LIMIT 1
),
top_cohort AS (
  -- Top quartile of cohort (index >= p75)
  SELECT cf.*
  FROM cohort_full cf
  CROSS JOIN cohort_pcts cp
  WHERE cf.instability_index >= cp.p75
),
top_stats AS (
  -- Aggregates for top quartile
  SELECT 
    AVG(hypo_episodes) AS top_avg_hypo,
    AVG(tachy_episodes) AS top_avg_tachy,
    AVG(los) AS top_avg_los,
    AVG(CAST(hospital_expire_flag AS NUMERIC)) AS top_mort_rate
  FROM top_cohort
),
gen_stats AS (
  -- Aggregates for general ICU population
  SELECT 
    AVG(hypo_episodes) AS gen_avg_hypo,
    AVG(tachy_episodes) AS gen_avg_tachy,
    AVG(los) AS gen_avg_los,
    AVG(CAST(hospital_expire_flag AS NUMERIC)) AS gen_mort_rate
  FROM all_with_vitals
)
-- Final output: p95 and comparisons
SELECT 
  cp.p95 AS p95_instability_index,
  ts.top_avg_hypo,
  ts.top_avg_tachy,
  ts.top_avg_los,
  ts.top_mort_rate,
  gs.gen_avg_hypo,
  gs.gen_avg_tachy,
  gs.gen_avg_los,
  gs.gen_mort_rate
FROM cohort_pcts cp
CROSS JOIN top_stats ts
CROSS JOIN gen_stats gs;