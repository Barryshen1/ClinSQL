WITH
-- ICU dictionary
icu_d_items AS (
  SELECT itemid, LOWER(label) AS label, LOWER(abbreviation) AS abbreviation
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
),

-- Identify itemids that likely correspond to RRT / dialysis (heuristic text match)
rrt_itemids AS (
  SELECT DISTINCT itemid
  FROM icu_d_items
  WHERE label LIKE '%dialysis%'
     OR label LIKE '%crrt%'
     OR label LIKE '%cvvh%'
     OR label LIKE '%cvvhd%'
     OR label LIKE '%renal replacement%'
     OR label LIKE '%hemodialysis%'
     OR abbreviation LIKE '%dialysis%'
),

-- Identify RRT ICU stays by scanning chartevents and procedureevents for matching itemids
rrt_stays AS (
  SELECT DISTINCT ce.subject_id, ce.hadm_id, ce.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN rrt_itemids r ON ce.itemid = r.itemid
  WHERE ce.charttime IS NOT NULL

  UNION DISTINCT

  SELECT DISTINCT pe.subject_id, pe.hadm_id, pe.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN rrt_itemids r ON pe.itemid = r.itemid
  WHERE pe.starttime IS NOT NULL
),

-- Identify vital sign itemid groups (heuristic text match)
hr_itemids AS (
  SELECT itemid FROM icu_d_items WHERE label LIKE '%heart rate%' OR label LIKE '%hr%'
),
rr_itemids AS (
  SELECT itemid FROM icu_d_items WHERE label LIKE '%respiratory rate%' OR label LIKE '%rr%'
),
sbp_itemids AS (
  -- systolic BP can be invasive or non-invasive; include typical label patterns
  SELECT itemid FROM icu_d_items WHERE label LIKE '%systolic%' AND (label LIKE '%blood pressure%' OR label LIKE '%bp%')
),
spo2_itemids AS (
  SELECT itemid FROM icu_d_items WHERE label LIKE '%oxygen saturation%' OR label LIKE '%spo2%' OR label LIKE '%oxy saturation%'
),
temp_itemids AS (
  SELECT itemid FROM icu_d_items WHERE label LIKE '%temperature%' OR label LIKE '%temp%'
),

-- Build cohort: ICU stays for female patients aged 52-62 who had RRT
cohort_stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime, i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN rrt_stays r
    ON i.subject_id = r.subject_id AND i.hadm_id = r.hadm_id AND i.stay_id = r.stay_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
),

-- Gather vitals in the first 72 hours of ICU stay and compute worst/aggregate values
vitals_first72 AS (
  SELECT
    cs.subject_id,
    cs.hadm_id,
    cs.stay_id,
    -- max heart rate within 72h
    MAX(CASE WHEN ce.itemid IN (SELECT itemid FROM hr_itemids) THEN ce.valuenum END) AS hr_max,
    -- max respiratory rate within 72h
    MAX(CASE WHEN ce.itemid IN (SELECT itemid FROM rr_itemids) THEN ce.valuenum END) AS rr_max,
    -- min systolic BP (consider all systolic itemids) within 72h
    MIN(CASE WHEN ce.itemid IN (SELECT itemid FROM sbp_itemids) THEN ce.valuenum END) AS sbp_min,
    -- min SpO2 within 72h
    MIN(CASE WHEN ce.itemid IN (SELECT itemid FROM spo2_itemids) THEN ce.valuenum END) AS spo2_min,
    -- max temperature within 72h
    MAX(CASE WHEN ce.itemid IN (SELECT itemid FROM temp_itemids) THEN ce.valuenum END) AS temp_max
  FROM cohort_stays cs
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.subject_id = cs.subject_id
    AND ce.stay_id = cs.stay_id
    AND ce.charttime >= cs.intime
    AND ce.charttime <= TIMESTAMP_ADD(cs.intime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY cs.subject_id, cs.hadm_id, cs.stay_id
),

-- Compute the instability score per stay using the chosen formula
scores AS (
  SELECT
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    v.hr_max,
    v.rr_max,
    v.sbp_min,
    v.spo2_min,
    v.temp_max,
    -- compute component contributions (threshold-based), treating missing components as zero contribution
    GREATEST(0, SAFE_CAST(v.hr_max AS FLOAT64) - 100)                                     AS hr_comp,
    GREATEST(0, SAFE_CAST(v.rr_max AS FLOAT64) - 20)                                      AS rr_comp,
    GREATEST(0, 90 - SAFE_CAST(v.sbp_min AS FLOAT64))                                     AS sbp_comp,
    GREATEST(0, 92 - SAFE_CAST(v.spo2_min AS FLOAT64))                                    AS spo2_comp,
    GREATEST(0, SAFE_CAST(v.temp_max AS FLOAT64) - 38)                                    AS temp_comp,
    -- total score; if all vitals NULL, score will be 0 but we will exclude stays with no vitals observed
    (GREATEST(0, SAFE_CAST(v.hr_max AS FLOAT64) - 100)
     + GREATEST(0, SAFE_CAST(v.rr_max AS FLOAT64) - 20)
     + GREATEST(0, 90 - SAFE_CAST(v.sbp_min AS FLOAT64))
     + GREATEST(0, 92 - SAFE_CAST(v.spo2_min AS FLOAT64))
     + GREATEST(0, SAFE_CAST(v.temp_max AS FLOAT64) - 38)
    ) AS instability_score
  FROM vitals_first72 v
),

-- Filter to stays with at least one vital measured in the first 72 hours (instability_score IS NOT NULL AND not all components null)
scored_cohort AS (
  SELECT s.*, cs.los
  FROM scores s
  JOIN cohort_stays cs USING(subject_id, hadm_id, stay_id)
  -- require that at least one vital was present (we check at least one of the raw vitals is not null)
  WHERE (s.hr_max IS NOT NULL OR s.rr_max IS NOT NULL OR s.sbp_min IS NOT NULL OR s.spo2_min IS NOT NULL OR s.temp_max IS NOT NULL)
),

-- Compute 90th percentile threshold for instability_score using APPROX_QUANTILES
quantiles AS (
  SELECT APPROX_QUANTILES(instability_score, 100) AS q_array
  FROM scored_cohort
),

threshold_90 AS (
  SELECT q_array[OFFSET(90)] AS q90
  FROM quantiles
),

-- Compute percentile of a score of 65 (percentage of cohort with instability_score <= 65)
percentile_calc AS (
  SELECT
    100.0 * SUM(CASE WHEN instability_score <= 65 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_of_65
  FROM scored_cohort
),

-- Top decile stays (instability_score >= 90th percentile threshold)
top_decile AS (
  SELECT sc.*
  FROM scored_cohort sc
  CROSS JOIN threshold_90 t
  WHERE sc.instability_score >= t.q90
),

-- For top decile, compute mean ICU LOS and mortality (hospital mortality)
top_decile_stats AS (
  SELECT
    COUNT(*) AS top_decile_count,
    AVG(los) AS mean_icu_los,
    -- hospital mortality using admissions.hospital_expire_flag
    AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS hospital_mortality_rate
  FROM top_decile td
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON td.hadm_id = a.hadm_id
)

-- Final output: percentile of 65 and top-decile summary
SELECT
  ROUND(pc.percentile_of_65, 2) AS percentile_of_score_65,
  t.q90 AS instability_score_90th_percentile_threshold,
  td.top_decile_count,
  ROUND(td.mean_icu_los, 3) AS mean_icu_los_top_decile_days,
  ROUND(td.hospital_mortality_rate * 100, 2) AS hospital_mortality_percent_top_decile
FROM percentile_calc pc
CROSS JOIN threshold_90 t
CROSS JOIN top_decile_stats td;