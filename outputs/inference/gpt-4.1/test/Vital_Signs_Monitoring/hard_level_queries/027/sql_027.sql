WITH
-- 1. Identify RRT itemids (CRRT, HD, etc.)
rrt_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%dialysis%'
     OR LOWER(label) LIKE '%crrt%'
     OR LOWER(label) LIKE '%renal replacement%'
),

-- 2. All ICU stays with RRT
rrt_stays AS (
  SELECT DISTINCT
    pe.subject_id,
    pe.hadm_id,
    pe.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN rrt_items ri ON pe.itemid = ri.itemid
),

-- 3. Add demographics and ICU info
rrt_patients AS (
  SELECT
    rs.subject_id,
    rs.hadm_id,
    rs.stay_id,
    p.gender,
    p.anchor_age,
    i.intime,
    i.outtime,
    i.los
  FROM rrt_stays rs
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON rs.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON rs.stay_id = i.stay_id
),

-- 4. Add mortality
rrt_patients_mort AS (
  SELECT
    rp.*,
    a.hospital_expire_flag
  FROM rrt_patients rp
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON rp.hadm_id = a.hadm_id
),

-- 5. Define target and comparator groups
target_group AS (
  SELECT * FROM rrt_patients_mort
  WHERE gender = 'F' AND anchor_age BETWEEN 58 AND 68
),
other_group AS (
  SELECT * FROM rrt_patients_mort
  WHERE NOT (gender = 'F' AND anchor_age BETWEEN 58 AND 68)
),

-- 6. MAP and HR itemids
map_items AS (
  SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
),
hr_items AS (
  SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%heart rate%'
),

-- 7. Get hourly MAP and HR for all RRT stays in first 72h
vitals AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    TIMESTAMP_DIFF(ce.charttime, i.intime, HOUR) AS hour_in_icu,
    CASE WHEN ce.itemid IN (SELECT itemid FROM map_items) THEN ce.valuenum ELSE NULL END AS map_val,
    CASE WHEN ce.itemid IN (SELECT itemid FROM hr_items) THEN ce.valuenum ELSE NULL END AS hr_val
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN rrt_patients_mort i ON ce.stay_id = i.stay_id
  WHERE TIMESTAMP_DIFF(ce.charttime, i.intime, HOUR) BETWEEN 0 AND 71
    AND ce.valuenum IS NOT NULL
    AND ce.itemid IN (
      SELECT itemid FROM map_items
      UNION ALL
      SELECT itemid FROM hr_items
    )
),

-- 8. Pivot to hourly bins per patient, get min MAP and max HR per hour
hourly_vitals AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    hour_in_icu,
    MIN(map_val) AS min_map,
    MAX(hr_val) AS max_hr
  FROM vitals
  GROUP BY subject_id, hadm_id, stay_id, hour_in_icu
),

-- 9. For each patient, count hours with hypotension, tachycardia, and both
vital_instability AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    COUNTIF(min_map < 65) AS hypotensive_hours,
    COUNTIF(max_hr > 100) AS tachycardic_hours,
    COUNTIF(min_map < 65 AND max_hr > 100) AS concurrent_hours,
    COUNT(*) AS total_hours -- hours with both MAP and HR available
  FROM hourly_vitals
  GROUP BY subject_id, hadm_id, stay_id
),

-- 10. Merge with patient info
target_vitals AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    t.stay_id,
    t.anchor_age,
    t.los,
    t.hospital_expire_flag,
    v.hypotensive_hours,
    v.tachycardic_hours,
    v.concurrent_hours,
    v.total_hours
  FROM target_group t
  LEFT JOIN vital_instability v
    ON t.subject_id = v.subject_id AND t.hadm_id = v.hadm_id AND t.stay_id = v.stay_id
),
other_vitals AS (
  SELECT
    o.subject_id,
    o.hadm_id,
    o.stay_id,
    o.anchor_age,
    o.los,
    o.hospital_expire_flag,
    v.hypotensive_hours,
    v.tachycardic_hours,
    v.concurrent_hours,
    v.total_hours
  FROM other_group o
  LEFT JOIN vital_instability v
    ON o.subject_id = v.subject_id AND o.hadm_id = v.hadm_id AND o.stay_id = v.stay_id
),

-- 11. Aggregate statistics for each group
target_stats AS (
  SELECT
    COUNT(*) AS n_patients,
    APPROX_QUANTILES(concurrent_hours, 100)[25] AS p25_vital_instability,
    APPROX_QUANTILES(concurrent_hours, 100)[50] AS p50_vital_instability,
    APPROX_QUANTILES(concurrent_hours, 100)[75] AS p75_vital_instability,
    APPROX_QUANTILES(concurrent_hours, 100)[90] AS p90_vital_instability,
    (APPROX_QUANTILES(concurrent_hours, 100)[75] - APPROX_QUANTILES(concurrent_hours, 100)[25]) AS iqr_vital_instability,
    AVG(hypotensive_hours) AS avg_hypotensive_hours,
    AVG(tachycardic_hours) AS avg_tachycardic_hours,
    AVG(concurrent_hours) AS avg_concurrent_hours,
    APPROX_QUANTILES(hypotensive_hours, 100)[50] AS median_hypotensive_hours,
    APPROX_QUANTILES(tachycardic_hours, 100)[50] AS median_tachycardic_hours,
    APPROX_QUANTILES(concurrent_hours, 100)[50] AS median_concurrent_hours,
    AVG(los) AS avg_icu_los,
    APPROX_QUANTILES(los, 100)[50] AS median_icu_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM target_vitals
),

other_stats AS (
  SELECT
    COUNT(*) AS n_patients,
    APPROX_QUANTILES(concurrent_hours, 100)[25] AS p25_vital_instability,
    APPROX_QUANTILES(concurrent_hours, 100)[50] AS p50_vital_instability,
    APPROX_QUANTILES(concurrent_hours, 100)[75] AS p75_vital_instability,
    APPROX_QUANTILES(concurrent_hours, 100)[90] AS p90_vital_instability,
    (APPROX_QUANTILES(concurrent_hours, 100)[75] - APPROX_QUANTILES(concurrent_hours, 100)[25]) AS iqr_vital_instability,
    AVG(hypotensive_hours) AS avg_hypotensive_hours,
    AVG(tachycardic_hours) AS avg_tachycardic_hours,
    AVG(concurrent_hours) AS avg_concurrent_hours,
    APPROX_QUANTILES(hypotensive_hours, 100)[50] AS median_hypotensive_hours,
    APPROX_QUANTILES(tachycardic_hours, 100)[50] AS median_tachycardic_hours,
    APPROX_QUANTILES(concurrent_hours, 100)[50] AS median_concurrent_hours,
    AVG(los) AS avg_icu_los,
    APPROX_QUANTILES(los, 100)[50] AS median_icu_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM other_vitals
)

-- 12. Final output
SELECT
  'Women 58-68 on RRT' AS group_label,
  * 
FROM target_stats
UNION ALL
SELECT
  'Other RRT patients' AS group_label,
  *
FROM other_stats
ORDER BY group_label
;