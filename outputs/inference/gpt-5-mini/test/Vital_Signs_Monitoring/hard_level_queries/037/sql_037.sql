WITH
-- 1) pick itemids for HR, RR, and MAP using d_items labels (flexible matching)
hr_itemids AS (
  SELECT ARRAY_AGG(itemid) AS ids
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%heart rate%'
),
rr_itemids AS (
  SELECT ARRAY_AGG(itemid) AS ids
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respiratory rate%' OR LOWER(label) LIKE '%resp rate%' OR LOWER(label) LIKE '%rr%'
),
map_itemids AS (
  SELECT ARRAY_AGG(itemid) AS ids
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE (LOWER(label) LIKE '%mean%' AND LOWER(label) LIKE '%blood pressure%')
     OR LOWER(label) LIKE '%mean arterial pressure%'
     OR LOWER(label) LIKE '%map%'
),

-- 2) For each icu stay, create hourly bins for first 72 hours
icu_hours AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag,
    hour_offset,
    TIMESTAMP_ADD(s.intime, INTERVAL hour_offset HOUR)                    AS hour_start,
    TIMESTAMP_ADD(s.intime, INTERVAL hour_offset + 1 HOUR)                AS hour_end
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p USING (subject_id)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a USING (hadm_id)
  CROSS JOIN UNNEST(GENERATE_ARRAY(0,71)) AS hour_offset
  WHERE s.intime IS NOT NULL
    AND TIMESTAMP_ADD(s.intime, INTERVAL hour_offset HOUR) < s.outtime  -- hour starts before outtime
    AND TIMESTAMP_ADD(s.intime, INTERVAL hour_offset HOUR) < TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR) -- within first 72h
),

-- 3) attach aggregated vital flags for each hour bin
hourly_flags AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.stay_id,
    h.intime,
    h.outtime,
    h.los,
    h.anchor_age,
    h.gender,
    h.hospital_expire_flag,
    h.hour_offset,
    h.hour_start,
    h.hour_end,

    -- HR: any measurement in hour, any tachy (valuenum > 100)
    MAX(CASE WHEN ce_hr.valuenum IS NOT NULL THEN 1 ELSE 0 END) AS any_hr_meas,
    MAX(CASE WHEN ce_hr.valuenum IS NOT NULL AND ce_hr.valuenum > 100 THEN 1 ELSE 0 END) AS any_hr_tachy,

    -- RR: any measurement in hour, any tachypnea (valuenum > 20)
    MAX(CASE WHEN ce_rr.valuenum IS NOT NULL THEN 1 ELSE 0 END) AS any_rr_meas,
    MAX(CASE WHEN ce_rr.valuenum IS NOT NULL AND ce_rr.valuenum > 20 THEN 1 ELSE 0 END) AS any_rr_tachy,

    -- MAP: any measurement in hour, any low MAP (valuenum < 65)
    MAX(CASE WHEN ce_map.valuenum IS NOT NULL THEN 1 ELSE 0 END) AS any_map_meas,
    MAX(CASE WHEN ce_map.valuenum IS NOT NULL AND ce_map.valuenum < 65 THEN 1 ELSE 0 END) AS any_map_low

  FROM icu_hours h
  LEFT JOIN (
    -- HR chart events in this hour
    SELECT ce.subject_id, ce.hadm_id, ce.stay_id, ce.charttime, ce.itemid, ce.valuenum
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN hr_itemids ON TRUE
    WHERE hr_itemids.ids IS NOT NULL
      AND ce.itemid IN UNNEST(hr_itemids.ids)
      AND ce.valuenum IS NOT NULL
  ) ce_hr
  ON ce_hr.stay_id = h.stay_id
    AND ce_hr.charttime >= h.hour_start
    AND ce_hr.charttime < h.hour_end

  LEFT JOIN (
    -- RR chart events in this hour
    SELECT ce.subject_id, ce.hadm_id, ce.stay_id, ce.charttime, ce.itemid, ce.valuenum
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN rr_itemids ON TRUE
    WHERE rr_itemids.ids IS NOT NULL
      AND ce.itemid IN UNNEST(rr_itemids.ids)
      AND ce.valuenum IS NOT NULL
  ) ce_rr
  ON ce_rr.stay_id = h.stay_id
    AND ce_rr.charttime >= h.hour_start
    AND ce_rr.charttime < h.hour_end

  LEFT JOIN (
    -- MAP chart events in this hour
    SELECT ce.subject_id, ce.hadm_id, ce.stay_id, ce.charttime, ce.itemid, ce.valuenum
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN map_itemids ON TRUE
    WHERE map_itemids.ids IS NOT NULL
      AND ce.itemid IN UNNEST(map_itemids.ids)
      AND ce.valuenum IS NOT NULL
  ) ce_map
  ON ce_map.stay_id = h.stay_id
    AND ce_map.charttime >= h.hour_start
    AND ce_map.charttime < h.hour_end

  GROUP BY
    h.subject_id, h.hadm_id, h.stay_id, h.intime, h.outtime, h.los, h.anchor_age, h.gender, h.hospital_expire_flag,
    h.hour_offset, h.hour_start, h.hour_end
),

-- 4) summarize per stay across the 72 hours
stay_summary AS (
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    intime,
    outtime,
    los,
    anchor_age,
    gender,
    hospital_expire_flag,

    -- monitored hours: any of the vitals measured in the hour
    SUM(CASE WHEN (any_hr_meas = 1 OR any_rr_meas = 1 OR any_map_meas = 1) THEN 1 ELSE 0 END) AS monitored_hours,
    SUM(CASE WHEN (any_hr_tachy = 1 OR any_rr_tachy = 1 OR any_map_low = 1) THEN 1 ELSE 0 END) AS unstable_hours,

    -- HR specific
    SUM(any_hr_meas) AS hr_hours,
    SUM(any_hr_tachy) AS hr_tachy_hours,

    -- RR specific
    SUM(any_rr_meas) AS rr_hours,
    SUM(any_rr_tachy) AS rr_tachy_hours,

    -- MAP specific
    SUM(any_map_meas) AS map_hours,
    SUM(any_map_low) AS map_low_hours

  FROM hourly_flags
  GROUP BY stay_id, subject_id, hadm_id, intime, outtime, los, anchor_age, gender, hospital_expire_flag
),

-- 5) compute composite score and per-vital rates per stay (exclude stays with zero monitored hours)
stay_scores AS (
  SELECT
    s.*,
    SAFE_DIVIDE(unstable_hours, monitored_hours) AS composite_instability,  -- NULL if monitored_hours = 0
    CASE WHEN hr_hours > 0 THEN SAFE_DIVIDE(hr_tachy_hours, hr_hours) ELSE NULL END AS hr_tachy_rate,
    CASE WHEN rr_hours > 0 THEN SAFE_DIVIDE(rr_tachy_hours, rr_hours) ELSE NULL END AS rr_tachy_rate,
    CASE WHEN map_hours > 0 THEN SAFE_DIVIDE(map_low_hours, map_hours) ELSE NULL END AS map_low_rate
  FROM stay_summary s
  WHERE monitored_hours > 0  -- exclude stays with no monitoring of these vitals in first 72h
),

-- 6) identify heart-failure admissions (hadm_id has a diagnosis with 'heart failure' in long_title)
hf_admissions AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(COALESCE(dd.long_title, '')) LIKE '%heart failure%'
),

-- 7) cohort: male patients age 45-55 with HF on that hadm_id
cohort_stays AS (
  SELECT ss.*
  FROM stay_scores ss
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p USING (subject_id)
  WHERE ss.gender = 'M'
    AND ss.anchor_age BETWEEN 45 AND 55
    AND ss.hadm_id IN (SELECT hadm_id FROM hf_admissions)
),

-- 8) cohort-level percentiles and quartile cutoff
cohort_percentiles AS (
  SELECT
    -- approximate 99th percentile of composite instability among cohort stays
    (APPROX_QUANTILES(composite_instability, 100))[OFFSET(99)] AS p99_composite,
    -- approximate 75th percentile for top quartile cutoff
    (APPROX_QUANTILES(composite_instability, 100))[OFFSET(75)] AS p75_composite
  FROM cohort_stays
),

-- 9) compute metrics for most unstable quartile within cohort
cohort_top_quartile_metrics AS (
  SELECT
    COUNT(*) AS num_stays_in_quartile,
    AVG(hr_tachy_rate) AS mean_hr_tachy_rate,        -- average fraction of HR-measured hours with HR>100
    AVG(rr_tachy_rate) AS mean_rr_tachy_rate,        -- average fraction of RR-measured hours with RR>20
    AVG(map_low_rate) AS mean_map_low_rate,          -- average fraction of MAP-measured hours with MAP<65
    AVG(los) AS mean_icu_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM cohort_stays cs
  CROSS JOIN cohort_percentiles cp
  WHERE cs.composite_instability >= cp.p75_composite
),

-- 10) compute metrics for the overall adult ICU population (>=18 yo)
population_metrics AS (
  SELECT
    COUNT(*) AS num_stays_population,
    AVG(hr_tachy_rate) AS mean_hr_tachy_rate,
    AVG(rr_tachy_rate) AS mean_rr_tachy_rate,
    AVG(map_low_rate) AS mean_map_low_rate,
    AVG(los) AS mean_icu_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM stay_scores ss
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p USING (subject_id)
  WHERE p.anchor_age >= 18
)

-- Final outputs: 99th percentile and comparison table
SELECT
  -- cohort-level percentile
  cp.p99_composite AS cohort_99th_percentile_composite,

  -- Quartile metrics for cohort (most unstable quartile)
  qt.num_stays_in_quartile AS cohort_top_quartile_n,
  qt.mean_hr_tachy_rate AS cohort_top_quartile_mean_hr_tachy_rate,
  qt.mean_map_low_rate AS cohort_top_quartile_mean_map_low_rate,
  qt.mean_rr_tachy_rate AS cohort_top_quartile_mean_rr_tachy_rate,
  qt.mean_icu_los_days AS cohort_top_quartile_mean_icu_los_days,
  qt.mortality_rate AS cohort_top_quartile_mortality_rate,

  -- Overall ICU population metrics for comparison
  pop.num_stays_population AS population_n,
  pop.mean_hr_tachy_rate AS population_mean_hr_tachy_rate,
  pop.mean_map_low_rate AS population_mean_map_low_rate,
  pop.mean_rr_tachy_rate AS population_mean_rr_tachy_rate,
  pop.mean_icu_los_days AS population_mean_icu_los_days,
  pop.mortality_rate AS population_mortality_rate

FROM cohort_percentiles cp
CROSS JOIN cohort_top_quartile_metrics qt
CROSS JOIN population_metrics pop;