WITH
-- 1) Identify MAP and HR itemids heuristically from d_items
vitals_itemids AS (
  SELECT
    itemid,
    CASE
      WHEN LOWER(label) LIKE '%mean arterial%' OR LOWER(label) LIKE '%map%' OR LOWER(abbreviation) LIKE '%map%' THEN 'map'
      WHEN LOWER(label) LIKE '%heart rate%' OR LOWER(abbreviation) LIKE '%hr%' OR LOWER(label) LIKE '%pulse rate%' THEN 'hr'
      ELSE NULL
    END AS vital_type
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial%'
     OR LOWER(label) LIKE '%map%'
     OR LOWER(label) LIKE '%heart rate%'
     OR LOWER(label) LIKE '%pulse rate%'
     OR LOWER(abbreviation) LIKE '%map%'
     OR LOWER(abbreviation) LIKE '%hr%'
),
-- keep only itemids we classified
vital_itemids_filtered AS (
  SELECT itemid, vital_type
  FROM vitals_itemids
  WHERE vital_type IS NOT NULL
),
-- 2) ICU stays filtered to female patients aged 59-69 and compute window for first 24h
stays_with_window AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR) AS intime_plus_24h,
    -- window_end = min(intime+24h, outtime) if outtime is not null, else intime+24h
    LEAST(TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR), COALESCE(s.outtime, TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR))) AS window_end,
    -- window seconds (observed time in first 24h)
    GREATEST(TIMESTAMP_DIFF(LEAST(TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR), COALESCE(s.outtime, TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR))), s.intime, SECOND), 0) AS window_seconds,
    s.los,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    -- shock flag: any diagnosis in the hadm with 'shock' in d_icd_diagnoses.long_title
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = s.hadm_id
        AND LOWER(dd.long_title) LIKE '%shock%'
    ) THEN 1 ELSE 0 END AS shock_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
),
-- 3) Pull relevant chartevents (MAP and HR) within the stay window and compute clipped durations per measurement
chart_with_durations AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    v.vital_type,
    c.itemid,
    c.charttime,
    c.valuenum,
    -- window boundaries from stay
    s.intime AS window_start,
    s.window_end,
    s.window_seconds,
    -- next charttime for the same stay+itemid (ordered by time)
    COALESCE(
      LEAST(
        LEAD(c.charttime) OVER (PARTITION BY c.stay_id, c.itemid ORDER BY c.charttime),
        s.window_end
      ),
      s.window_end
    ) AS next_time_clipped,
    -- clipped start: measurement time clipped to window_start (should be >= window_start due to WHERE clause)
    GREATEST(c.charttime, s.intime) AS clipped_start
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN vital_itemids_filtered v
    ON c.itemid = v.itemid
  JOIN stays_with_window s
    ON c.stay_id = s.stay_id
  WHERE
    -- keep only numeric values
    c.valuenum IS NOT NULL
    -- keep only events that start within the window (>= intime and < window_end)
    AND c.charttime >= s.intime
    AND c.charttime < s.window_end
),
-- compute duration in seconds each measurement value is assumed to last (until next_time_clipped)
chart_durations AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    vital_type,
    itemid,
    charttime,
    valuenum,
    window_start,
    window_end,
    window_seconds,
    next_time_clipped,
    clipped_start,
    -- duration only if next_time_clipped > clipped_start
    CASE
      WHEN next_time_clipped > clipped_start THEN TIMESTAMP_DIFF(next_time_clipped, clipped_start, SECOND)
      ELSE 0
    END AS duration_seconds
  FROM chart_with_durations
),
-- 4) For each stay compute total seconds meeting each condition
per_stay_burden AS (
  SELECT
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    s.window_seconds,
    s.los,
    s.shock_flag,
    s.hospital_expire_flag,
    -- total seconds MAP is < 65
    SUM(CASE WHEN cd.vital_type = 'map' AND cd.valuenum < 65 THEN cd.duration_seconds ELSE 0 END) AS hypotension_seconds,
    -- total seconds HR > 100
    SUM(CASE WHEN cd.vital_type = 'hr' AND cd.valuenum > 100 THEN cd.duration_seconds ELSE 0 END) AS tachy_seconds,
    -- also count total MAP/HR measurement-covered seconds (optional)
    SUM(CASE WHEN cd.vital_type = 'map' THEN cd.duration_seconds ELSE 0 END) AS map_measured_seconds,
    SUM(CASE WHEN cd.vital_type = 'hr' THEN cd.duration_seconds ELSE 0 END) AS hr_measured_seconds
  FROM stays_with_window s
  LEFT JOIN chart_durations cd
    ON s.stay_id = cd.stay_id
  GROUP BY s.stay_id, s.subject_id, s.hadm_id, s.window_seconds, s.los, s.shock_flag, s.hospital_expire_flag
),
-- 5) Derive per-stay percentages and composite score
per_stay_scores AS (
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    shock_flag,
    hospital_expire_flag,
    los,
    window_seconds,
    -- Use window_seconds as denominator (observed time in first-24h window)
    SAFE_DIVIDE(hypotension_seconds, NULLIF(window_seconds,0)) * 100.0 AS hypotension_pct,
    SAFE_DIVIDE(tachy_seconds, NULLIF(window_seconds,0)) * 100.0 AS tachycardia_pct,
    -- composite = sum of the two percent burdens
    SAFE_DIVIDE(hypotension_seconds, NULLIF(window_seconds,0)) * 100.0
      + SAFE_DIVIDE(tachy_seconds, NULLIF(window_seconds,0)) * 100.0 AS composite_instability_score
  FROM per_stay_burden
  WHERE window_seconds > 0  -- exclude zero-length windows
),
-- 6) Final grouped stats (shock vs no shock)
grouped_stats AS (
  SELECT
    shock_flag,
    COUNT(1) AS n_stays,
    -- means
    AVG(composite_instability_score) AS mean_composite,
    AVG(hypotension_pct) AS mean_hypotension_pct,
    AVG(tachycardia_pct) AS mean_tachycardia_pct,
    AVG(los) AS mean_icu_los_days,
    100.0 * AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_percent,
    -- percentiles using APPROX_QUANTILES (returns array of 101 values: 0..100th percentiles)
    APPROX_QUANTILES(composite_instability_score, 100) AS composite_q_arr,
    APPROX_QUANTILES(hypotension_pct, 100) AS hypotension_q_arr,
    APPROX_QUANTILES(tachycardia_pct, 100) AS tachy_q_arr,
    APPROX_QUANTILES(los, 100) AS los_q_arr
  FROM per_stay_scores
  GROUP BY shock_flag
)
-- Select final formatted percentiles by indexing into the quantile arrays
SELECT
  shock_flag,
  n_stays,
  mean_composite,
  -- composite percentiles: 10th,25th,50th,75th,90th -> offsets 10,25,50,75,90
  SAFE_CAST(composite_q_arr[OFFSET(10)] AS FLOAT64) AS composite_p10,
  SAFE_CAST(composite_q_arr[OFFSET(25)] AS FLOAT64) AS composite_p25,
  SAFE_CAST(composite_q_arr[OFFSET(50)] AS FLOAT64) AS composite_p50,
  SAFE_CAST(composite_q_arr[OFFSET(75)] AS FLOAT64) AS composite_p75,
  SAFE_CAST(composite_q_arr[OFFSET(90)] AS FLOAT64) AS composite_p90,
  mean_hypotension_pct,
  SAFE_CAST(hypotension_q_arr[OFFSET(10)] AS FLOAT64) AS hypotension_p10,
  SAFE_CAST(hypotension_q_arr[OFFSET(25)] AS FLOAT64) AS hypotension_p25,
  SAFE_CAST(hypotension_q_arr[OFFSET(50)] AS FLOAT64) AS hypotension_p50,
  SAFE_CAST(hypotension_q_arr[OFFSET(75)] AS FLOAT64) AS hypotension_p75,
  SAFE_CAST(hypotension_q_arr[OFFSET(90)] AS FLOAT64) AS hypotension_p90,
  mean_tachycardia_pct,
  SAFE_CAST(tachy_q_arr[OFFSET(10)] AS FLOAT64) AS tachy_p10,
  SAFE_CAST(tachy_q_arr[OFFSET(25)] AS FLOAT64) AS tachy_p25,
  SAFE_CAST(tachy_q_arr[OFFSET(50)] AS FLOAT64) AS tachy_p50,
  SAFE_CAST(tachy_q_arr[OFFSET(75)] AS FLOAT64) AS tachy_p75,
  SAFE_CAST(tachy_q_arr[OFFSET(90)] AS FLOAT64) AS tachy_p90,
  mean_icu_los_days,
  SAFE_CAST(los_q_arr[OFFSET(10)] AS FLOAT64) AS los_p10,
  SAFE_CAST(los_q_arr[OFFSET(25)] AS FLOAT64) AS los_p25,
  SAFE_CAST(los_q_arr[OFFSET(50)] AS FLOAT64) AS los_p50,
  SAFE_CAST(los_q_arr[OFFSET(75)] AS FLOAT64) AS los_p75,
  SAFE_CAST(los_q_arr[OFFSET(90)] AS FLOAT64) AS los_p90,
  mortality_percent
FROM grouped_stats
ORDER BY shock_flag DESC;