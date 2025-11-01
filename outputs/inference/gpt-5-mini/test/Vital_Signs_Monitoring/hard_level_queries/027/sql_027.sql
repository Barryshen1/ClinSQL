WITH rrt_admissions AS (
  -- admissions that had a dialysis / renal replacement procedure (hadm-level)
  SELECT DISTINCT p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code
   AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%dialysis%'
     OR LOWER(d.long_title) LIKE '%hemodialysis%'
     OR LOWER(d.long_title) LIKE '%renal replacement%'
     OR LOWER(d.long_title) LIKE '%hemofiltration%'
     OR LOWER(d.long_title) LIKE '%continuous%'
     OR LOWER(d.long_title) LIKE '%crrt%'
),

map_hr_items AS (
  -- Map MAP and HR itemids from ICU d_items (labels matched heuristically)
  SELECT itemid,
         LOWER(label) AS label,
         CASE
           WHEN LOWER(label) LIKE '%mean arterial%' OR LOWER(label) LIKE '%map%' THEN 'MAP'
           WHEN LOWER(label) LIKE '%heart rate%' OR LOWER(label) LIKE '%hr%' OR LOWER(label) LIKE '%pulse%' THEN 'HR'
           ELSE NULL
         END AS kind
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial%'
     OR LOWER(label) LIKE '%map%'
     OR LOWER(label) LIKE '%heart rate%'
     OR LOWER(label) LIKE '%hr%'
     OR LOWER(label) LIKE '%pulse%'
),

map_events AS (
  -- MAP measurements (all times; will be restricted to first 72h later)
  SELECT ce.subject_id, ce.hadm_id, ce.stay_id,
         ce.charttime,
         ce.valuenum AS map_val,
         TIMESTAMP_TRUNC(ce.charttime, MINUTE) AS chart_min,
         TIMESTAMP_TRUNC(ce.charttime, HOUR)   AS chart_hour
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN map_hr_items i ON ce.itemid = i.itemid
  WHERE i.kind = 'MAP'
    AND ce.valuenum IS NOT NULL
),

hr_events AS (
  -- HR measurements (all times; will be restricted to first 72h later)
  SELECT ce.subject_id, ce.hadm_id, ce.stay_id,
         ce.charttime,
         ce.valuenum AS hr_val,
         TIMESTAMP_TRUNC(ce.charttime, MINUTE) AS chart_min,
         TIMESTAMP_TRUNC(ce.charttime, HOUR)   AS chart_hour
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN map_hr_items i ON ce.itemid = i.itemid
  WHERE i.kind = 'HR'
    AND ce.valuenum IS NOT NULL
),

icu_rrt_stays AS (
  -- ICU stays that belong to RRT admissions
  SELECT icu.*
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  WHERE icu.hadm_id IN (SELECT hadm_id FROM rrt_admissions)
),

stay_time_window AS (
  -- define first 72h window per stay
  SELECT s.*,
         s.intime AS window_start,
         LEAST(s.outtime, TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)) AS window_end
  FROM icu_rrt_stays s
),

-- restrict events to each stay's first 72 hours
stay_map_events AS (
  SELECT me.*
  FROM map_events me
  JOIN stay_time_window st
    ON me.stay_id = st.stay_id
   AND me.charttime BETWEEN st.window_start AND st.window_end
),

stay_hr_events AS (
  SELECT he.*
  FROM hr_events he
  JOIN stay_time_window st
    ON he.stay_id = st.stay_id
   AND he.charttime BETWEEN st.window_start AND st.window_end
),

-- concurrent-minute pairs (minute-granularity matching)
concurrent_minute AS (
  SELECT m.subject_id, m.hadm_id, m.stay_id, m.chart_min,
         -- if multiple values per minute, use avg to summarize that minute
         AVG(m.map_val) AS map_mean_min,
         AVG(h.hr_val)  AS hr_mean_min
  FROM stay_map_events m
  JOIN stay_hr_events h
    ON m.stay_id = h.stay_id
   AND m.chart_min = h.chart_min
  GROUP BY m.subject_id, m.hadm_id, m.stay_id, m.chart_min
),

-- per-stay computed metrics
stay_metrics AS (
  SELECT st.stay_id,
         st.subject_id,
         st.hadm_id,
         p.gender,
         p.anchor_age,
         st.los AS icu_los_days,
         adm.hospital_expire_flag,
         -- total concurrent minutes where both MAP&HR exist
         COUNT(cm.chart_min) AS n_concurrent_minutes,
         -- count minutes with instability condition
         SUM(CASE WHEN cm.map_mean_min < 65 AND cm.hr_mean_min > 100 THEN 1 ELSE 0 END) AS n_instability_minutes,
         -- vital-instability index: proportion of concurrent minutes with MAP<65 & HR>100
         SAFE_DIVIDE(
           SUM(CASE WHEN cm.map_mean_min < 65 AND cm.hr_mean_min > 100 THEN 1 ELSE 0 END),
           NULLIF(COUNT(cm.chart_min), 0)
         ) AS vital_instability_index,
         -- hypotensive hours: distinct hours with at least one MAP<65
         (SELECT COUNT(DISTINCT m.chart_hour)
          FROM stay_map_events m
          WHERE m.stay_id = st.stay_id
            AND m.map_val < 65) AS hypotensive_hours,
         -- tachycardic hours: distinct hours with at least one HR>100
         (SELECT COUNT(DISTINCT h.chart_hour)
          FROM stay_hr_events h
          WHERE h.stay_id = st.stay_id
            AND h.hr_val > 100) AS tachy_hours
  FROM stay_time_window st
  LEFT JOIN concurrent_minute cm ON st.stay_id = cm.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON st.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON st.hadm_id = adm.hadm_id
  GROUP BY st.stay_id, st.subject_id, st.hadm_id, p.gender, p.anchor_age, st.los, adm.hospital_expire_flag
),

-- tag target vs other RRT
stay_grouped AS (
  SELECT sm.*,
         CASE
           WHEN sm.gender = 'F' AND sm.anchor_age BETWEEN 58 AND 68 THEN 'Female_58_68'
           ELSE 'Other_RRT'
         END AS rrt_group
  FROM stay_metrics sm
)

-- final aggregation: percentiles for vital-instability index and median/IQRs for hours, LOS; mortality rate
SELECT
  rrt_group,
  COUNT(*) AS n_stays,
  -- Vital-instability index percentiles (only non-null indices included)
  APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(25)] AS vi_p25,
  APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(50)] AS vi_p50,
  APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(75)] AS vi_p75,
  APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(90)] AS vi_p90,
  -- IQR = 75th - 25th
  SAFE_SUBTRACT(
    APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(75)],
    APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(25)]
  ) AS vi_iqr,
  -- Hypotensive hours median and IQR
  APPROX_QUANTILES(hypotensive_hours, 100)[OFFSET(50)] AS hypotensive_hours_median,
  APPROX_QUANTILES(hypotensive_hours, 100)[OFFSET(75)] AS hypotensive_hours_p75,
  APPROX_QUANTILES(hypotensive_hours, 100)[OFFSET(25)] AS hypotensive_hours_p25,
  SAFE_SUBTRACT(
    APPROX_QUANTILES(hypotensive_hours, 100)[OFFSET(75)],
    APPROX_QUANTILES(hypotensive_hours, 100)[OFFSET(25)]
  ) AS hypotensive_hours_iqr,
  -- Tachycardic hours median and IQR
  APPROX_QUANTILES(tachy_hours, 100)[OFFSET(50)] AS tachy_hours_median,
  APPROX_QUANTILES(tachy_hours, 100)[OFFSET(75)] AS tachy_hours_p75,
  APPROX_QUANTILES(tachy_hours, 100)[OFFSET(25)] AS tachy_hours_p25,
  SAFE_SUBTRACT(
    APPROX_QUANTILES(tachy_hours, 100)[OFFSET(75)],
    APPROX_QUANTILES(tachy_hours, 100)[OFFSET(25)]
  ) AS tachy_hours_iqr,
  -- ICU LOS median and IQR (days)
  APPROX_QUANTILES(icu_los_days, 100)[OFFSET(50)] AS icu_los_median_days,
  APPROX_QUANTILES(icu_los_days, 100)[OFFSET(75)] AS icu_los_p75_days,
  APPROX_QUANTILES(icu_los_days, 100)[OFFSET(25)] AS icu_los_p25_days,
  SAFE_SUBTRACT(
    APPROX_QUANTILES(icu_los_days, 100)[OFFSET(75)],
    APPROX_QUANTILES(icu_los_days, 100)[OFFSET(25)]
  ) AS icu_los_iqr_days,
  -- Mortality rate (in-hospital)
  SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS INT64)), COUNT(*)) AS inhospital_mortality_rate
FROM stay_grouped
GROUP BY rrt_group
ORDER BY rrt_group;