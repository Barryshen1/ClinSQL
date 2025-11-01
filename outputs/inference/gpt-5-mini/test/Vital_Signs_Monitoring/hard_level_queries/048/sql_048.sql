WITH patients_female_75_85 AS (
  SELECT subject_id, gender, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 75 AND 85
),

icu_population AS (
  SELECT i.*
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN patients_female_75_85 p
    ON i.subject_id = p.subject_id
),

-- Identify stays with a coded mechanical ventilation procedure (using procedure text matching)
ventilation_procs AS (
  SELECT DISTINCT i.stay_id
  FROM icu_population i
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON pr.hadm_id = i.hadm_id
    AND pr.subject_id = i.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pr.icd_code = dp.icd_code
    AND pr.icd_version = dp.icd_version
  WHERE (
      LOWER(dp.long_title) LIKE '%ventilat%'    -- captures 'ventilation', 'ventilator'
      OR LOWER(dp.long_title) LIKE '%mechanical ventil%'  -- explicit phrase
      OR LOWER(dp.long_title) LIKE '%mechanical ventilation%'
      OR LOWER(dp.long_title) LIKE '%ventilator%'
    )
    -- require the procedure date to be during the ICU stay or within first 48 hours of ICU admission
    AND DATE(pr.chartdate) BETWEEN DATE(i.intime) AND DATE_ADD(DATE(i.intime), INTERVAL 2 DAY)
),

-- Final cohort: icu stays that meet patient criteria and ventilation procedure criteria
cohort_stays AS (
  SELECT i.*
  FROM icu_population i
  JOIN ventilation_procs v
    ON i.stay_id = v.stay_id
),

-- Pull HR, MAP, and SBP measurements in first 48 hours after ICU intime
vital_events AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    di.itemid,
    LOWER(di.label) AS label,
    c.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON c.itemid = di.itemid
  JOIN cohort_stays s
    ON c.stay_id = s.stay_id
  WHERE c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
    AND c.valuenum IS NOT NULL
    -- identify HR / MAP / SBP by label text heuristics
    AND (
      (LOWER(di.label) LIKE '%heart%' AND LOWER(di.label) LIKE '%rate%')   -- heart rate
      OR LOWER(di.label) LIKE '%pulse%'                                   -- pulse may reflect HR
      OR (LOWER(di.label) LIKE '%mean%' AND LOWER(di.label) LIKE '%arterial%') -- MAP
      OR LOWER(di.label) LIKE '%map%'                                     -- MAP abbreviation
      OR LOWER(di.label) LIKE '%systolic%'                                -- SBP
    )
),

-- Classify each measurement into type and whether it's 'unstable' by our thresholds
classified_vitals AS (
  SELECT
    ve.*,
    CASE
      WHEN ((LOWER(label) LIKE '%heart%' AND LOWER(label) LIKE '%rate%')
            OR LOWER(label) LIKE '%pulse%') THEN 'hr'
      WHEN ((LOWER(label) LIKE '%mean%' AND LOWER(label) LIKE '%arterial%')
            OR LOWER(label) LIKE '%map%') THEN 'map'
      WHEN LOWER(label) LIKE '%systolic%' THEN 'sbp'
      ELSE 'other'
    END AS meas_type,
    -- instability flags per measurement event
    CASE
      WHEN (((LOWER(label) LIKE '%heart%' AND LOWER(label) LIKE '%rate%') OR LOWER(label) LIKE '%pulse%') AND ve.valuenum > 100) THEN 1
      WHEN (((LOWER(label) LIKE '%mean%' AND LOWER(label) LIKE '%arterial%') OR LOWER(label) LIKE '%map%') AND ve.valuenum < 65) THEN 1
      WHEN (LOWER(label) LIKE '%systolic%' AND ve.valuenum < 90) THEN 1
      ELSE 0
    END AS is_unstable,
    -- flags for hypotension / tachycardia for per-stay any-event calculations
    CASE
      WHEN (((LOWER(label) LIKE '%mean%' AND LOWER(label) LIKE '%arterial%') OR LOWER(label) LIKE '%map%') AND ve.valuenum < 65) THEN 1
      WHEN (LOWER(label) LIKE '%systolic%' AND ve.valuenum < 90) THEN 1
      ELSE 0
    END AS is_hypotension_event,
    CASE
      WHEN (((LOWER(label) LIKE '%heart%' AND LOWER(label) LIKE '%rate%') OR LOWER(label) LIKE '%pulse%') AND ve.valuenum > 100) THEN 1
      ELSE 0
    END AS is_tachy_event
  FROM vital_events ve
),

-- Per-stay statistics for the first 48 hours
per_stay_stats AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    COUNT(*) AS total_measurements,
    SUM(is_unstable) AS instability_count,
    -- any hypotension / tachycardia in first 48h
    MAX(is_hypotension_event) AS any_hypotension,
    MAX(is_tachy_event) AS any_tachycardia
  FROM classified_vitals v
  JOIN cohort_stays s
    ON v.stay_id = s.stay_id
  GROUP BY s.subject_id, s.hadm_id, s.stay_id, s.intime, s.outtime, s.los
),

-- Include stays that had no matching vitals in the first 48h (assign zero counts)
per_stay_all AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    COALESCE(p.total_measurements, 0) AS total_measurements,
    COALESCE(p.instability_count, 0) AS instability_count,
    COALESCE(p.any_hypotension, 0) AS any_hypotension,
    COALESCE(p.any_tachycardia, 0) AS any_tachycardia
  FROM cohort_stays s
  LEFT JOIN per_stay_stats p
    ON s.stay_id = p.stay_id
),

-- Compute composite instability score per stay (as percent of measured events that were abnormal)
per_stay_scores AS (
  SELECT
    *,
    CASE
      WHEN total_measurements > 0 THEN 100.0 * instability_count / total_measurements
      ELSE 0.0
    END AS composite_score_48h
  FROM per_stay_all
),

-- Compute percentiles (approximate) across the cohort
percentiles AS (
  SELECT
    (APPROX_QUANTILES(composite_score_48h, 100))[OFFSET(90)] AS percentile_90,
    (APPROX_QUANTILES(composite_score_48h, 100))[OFFSET(75)] AS percentile_75
  FROM per_stay_scores
),

-- Identify top 25% stays (composite_score >= 75th percentile)
top_quartile_stays AS (
  SELECT s.*
  FROM per_stay_scores s
  CROSS JOIN percentiles p
  WHERE s.composite_score_48h >= p.percentile_75
),

-- For top quartile compute requested summary stats
top_quartile_summary AS (
  SELECT
    COUNT(*) AS n_stays_top_quartile,
    SUM(any_hypotension) AS n_hypotension,
    100.0 * AVG(CAST(any_hypotension AS FLOAT64)) AS pct_with_hypotension,
    SUM(any_tachycardia) AS n_tachy,
    100.0 * AVG(CAST(any_tachycardia AS FLOAT64)) AS pct_with_tachycardia,
    -- ICU LOS: mean and median (median approximated)
    AVG(los) AS mean_icu_los_days,
    (APPROX_QUANTILES(los, 2))[OFFSET(1)] AS median_icu_los_days
  FROM top_quartile_stays
),

-- Mortality in top quartile: join to admissions.hospital_expire_flag
top_quartile_mortality AS (
  SELECT
    SUM(CAST(a.hospital_expire_flag AS INT64)) AS n_deaths_hospital,
    100.0 * AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS pct_hospital_mortality
  FROM top_quartile_stays s
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id
)

-- Final output: 90th percentile and top-quartile statistics
SELECT
  p.percentile_90 AS composite_score_48h_90th_percentile,
  p.percentile_75 AS composite_score_48h_75th_percentile_for_top25,
  tq.n_stays_top_quartile,
  tq.n_hypotension,
  tq.pct_with_hypotension,
  tq.n_tachy,
  tq.pct_with_tachycardia,
  tq.mean_icu_los_days,
  tq.median_icu_los_days,
  tm.n_deaths_hospital,
  tm.pct_hospital_mortality
FROM percentiles p
CROSS JOIN top_quartile_summary tq
CROSS JOIN top_quartile_mortality tm;