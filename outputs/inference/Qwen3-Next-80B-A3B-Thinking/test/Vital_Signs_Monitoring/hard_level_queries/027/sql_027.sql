WITH map_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%MAP%' OR label LIKE '%Mean Arterial Pressure%'
),
hr_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%Heart Rate%' OR label LIKE '%HR%'
),
rrt_stays AS (
  SELECT DISTINCT pe.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE di.label LIKE '%dialysis%' OR di.label LIKE '%RRT%'
),
rrt_patients AS (
  SELECT 
    i.stay_id,
    i.intime,
    i.outtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  JOIN rrt_stays rs ON i.stay_id = rs.stay_id
),
chartevents_data AS (
  SELECT 
    c.stay_id,
    c.charttime,
    c.itemid,
    c.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  WHERE (c.itemid IN (SELECT itemid FROM map_items) 
    OR c.itemid IN (SELECT itemid FROM hr_items))
    AND c.valuenum IS NOT NULL
),
hourly_data AS (
  SELECT 
    stay_id,
    TIMESTAMP_TRUNC(charttime, HOUR) AS hour,
    AVG(CASE WHEN itemid IN (SELECT itemid FROM map_items) THEN valuenum END) AS avg_map,
    AVG(CASE WHEN itemid IN (SELECT itemid FROM hr_items) THEN valuenum END) AS avg_hr
  FROM chartevents_data
  GROUP BY stay_id, hour
),
first_72h AS (
  SELECT 
    h.stay_id,
    h.hour,
    h.avg_map,
    h.avg_hr,
    r.intime
  FROM hourly_data h
  JOIN rrt_patients r ON h.stay_id = r.stay_id
  WHERE h.hour >= r.intime AND h.hour < r.intime + INTERVAL 72 HOUR
),
metrics AS (
  SELECT 
    r.stay_id,
    r.gender,
    r.age_at_admission,
    r.hospital_expire_flag,
    SUM(CASE WHEN avg_map < 65 AND avg_hr > 100 THEN 1 ELSE 0 END) AS concurrent_hours,
    SUM(CASE WHEN avg_map < 65 THEN 1 ELSE 0 END) AS hypotensive_hours,
    SUM(CASE WHEN avg_hr > 100 THEN 1 ELSE 0 END) AS tachycardic_hours,
    DATETIME_DIFF(r.outtime, r.intime, HOUR) AS icu_los_hours
  FROM rrt_patients r
  LEFT JOIN first_72h f ON r.stay_id = f.stay_id
  GROUP BY r.stay_id, r.gender, r.age_at_admission, r.hospital_expire_flag, r.intime, r.outtime
),
rrt_group AS (
  SELECT 
    concurrent_hours / 72.0 AS vital_index,
    hypotensive_hours,
    tachycardic_hours,
    icu_los_hours,
    hospital_expire_flag
  FROM metrics
  WHERE gender = 'F' AND age_at_admission BETWEEN 58 AND 68
),
other_rrt AS (
  SELECT 
    concurrent_hours / 72.0 AS vital_index,
    hypotensive_hours,
    tachycardic_hours,
    icu_los_hours,
    hospital_expire_flag
  FROM metrics
  WHERE NOT (gender = 'F' AND age_at_admission BETWEEN 58 AND 68)
),
vital_percentiles AS (
  SELECT 
    'vital_index' AS metric,
    '58-68 group' AS group_name,
    PERCENTILE_CONT(vital_index, 0.25) AS p25,
    PERCENTILE_CONT(vital_index, 0.5) AS p50,
    PERCENTILE_CONT(vital_index, 0.75) AS p75,
    PERCENTILE_CONT(vital_index, 0.9) AS p90,
    (PERCENTILE_CONT(vital_index, 0.75) - PERCENTILE_CONT(vital_index, 0.25)) AS iqr
  FROM rrt_group
),
metric_averages AS (
  SELECT 
    'hypotensive_hours' AS metric,
    '58-68 group' AS group_name,
    AVG(hypotensive_hours) AS value
  FROM rrt_group
  UNION ALL
  SELECT 
    'hypotensive_hours' AS metric,
    'other RRT' AS group_name,
    AVG(hypotensive_hours) AS value
  FROM other_rrt
  UNION ALL
  SELECT 
    'tachycardic_hours' AS metric,
    '58-68 group' AS group_name,
    AVG(tachycardic_hours) AS value
  FROM rrt_group
  UNION ALL
  SELECT 
    'tachycardic_hours' AS metric,
    'other RRT' AS group_name,
    AVG(tachycardic_hours) AS value
  FROM other_rrt
  UNION ALL
  SELECT 
    'icu_los_hours' AS metric,
    '58-68 group' AS group_name,
    AVG(icu_los_hours) AS value
  FROM rrt_group
  UNION ALL
  SELECT 
    'icu_los_hours' AS metric,
    'other RRT' AS group_name,
    AVG(icu_los_hours) AS value
  FROM other_rrt
  UNION ALL
  SELECT 
    'mortality_rate' AS metric,
    '58-68 group' AS group_name,
    AVG(hospital_expire_flag) AS value
  FROM rrt_group
  UNION ALL
  SELECT 
    'mortality_rate' AS metric,
    'other RRT' AS group_name,
    AVG(hospital_expire_flag) AS value
  FROM other_rrt
)
SELECT * FROM vital_percentiles
UNION ALL
SELECT * FROM metric_averages;