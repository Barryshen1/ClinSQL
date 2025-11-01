WITH rrt_patients AS (
  SELECT DISTINCT stay_id, subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.inputevents`
  WHERE ordercategoryname IN ('Continuous Renal Replacement Therapy', 'Dialysis')
),
patient_info AS (
  SELECT 
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id
  JOIN rrt_patients r ON i.stay_id = r.stay_id
),
cohort AS (
  SELECT 
    r.subject_id,
    r.hadm_id,
    r.stay_id,
    CASE WHEN p.gender = 'F' AND p.age_at_icu BETWEEN 58 AND 68 THEN 'A' ELSE 'B' END AS group_label
  FROM rrt_patients r
  JOIN patient_info p ON r.subject_id = p.subject_id
),
vital_measurements AS (
  SELECT 
    c.stay_id,
    c.group_label,
    i.intime,
    ce.charttime,
    CASE WHEN ce.itemid IN (455, 6701, 6702, 220052, 225312) THEN ce.valuenum END AS map_value,
    CASE WHEN ce.itemid IN (211, 220045) THEN ce.valuenum END AS hr_value
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON c.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON c.stay_id = ce.stay_id 
    AND ce.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 72 HOUR)
    AND ce.itemid IN (455, 6701, 6702, 220052, 225312, 211, 220045)
    AND ce.valuenum IS NOT NULL
),
hourly_vitals AS (
  SELECT
    stay_id,
    group_label,
    EXTRACT(HOUR FROM charttime - intime) AS hour,
    ARRAY_AGG(map_value IGNORE NULLS ORDER BY charttime DESC LIMIT 1)[SAFE_OFFSET(0)] AS last_map,
    ARRAY_AGG(hr_value IGNORE NULLS ORDER BY charttime DESC LIMIT 1)[SAFE_OFFSET(0)] AS last_hr
  FROM vital_measurements
  GROUP BY stay_id, group_label, hour
  HAVING hour < 72
),
patient_stats AS (
  SELECT
    stay_id,
    group_label,
    COUNT(*) AS total_hours,
    COUNTIF(last_map < 65 AND last_hr > 100) AS unstable_hours,
    COUNTIF(last_map < 65) AS hypotensive_hours,
    COUNTIF(last_hr > 100) AS tachycardic_hours,
    SAFE_DIVIDE(COUNTIF(last_map < 65 AND last_hr > 100), COUNT(*)) AS vital_instability_index
  FROM hourly_vitals
  GROUP BY stay_id, group_label
),
icu_los_mortality AS (
  SELECT
    i.stay_id,
    i.los AS icu_los_days,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
),
final_stats AS (
  SELECT
    ps.stay_id,
    ps.group_label,
    ps.vital_instability_index,
    ps.hypotensive_hours,
    ps.tachycardic_hours,
    ilm.icu_los_days,
    ilm.hospital_expire_flag
  FROM patient_stats ps
  JOIN icu_los_mortality ilm ON ps.stay_id = ilm.stay_id
),
part1 AS (
  SELECT
    'vital_instability_index' AS metric,
    'p25' AS percentile,
    APPROX_QUANTILES(vital_instability_index, 1000)[OFFSET(250)] AS value,
    'A' AS group_label
  FROM final_stats
  WHERE group_label = 'A'
  UNION ALL
  SELECT
    'vital_instability_index',
    'p50',
    APPROX_QUANTILES(vital_instability_index, 1000)[OFFSET(500)],
    'A'
  FROM final_stats
  WHERE group_label = 'A'
  UNION ALL
  SELECT
    'vital_instability_index',
    'p75',
    APPROX_QUANTILES(vital_instability_index, 1000)[OFFSET(750)],
    'A'
  FROM final_stats
  WHERE group_label = 'A'
  UNION ALL
  SELECT
    'vital_instability_index',
    'p90',
    APPROX_QUANTILES(vital_instability_index, 1000)[OFFSET(900)],
    'A'
  FROM final_stats
  WHERE group_label = 'A'
),
part2 AS (
  SELECT
    'hypotensive_hours' AS metric,
    percentile,
    value,
    group_label
  FROM (
    SELECT
      group_label,
      APPROX_QUANTILES(hypotensive_hours, 1000)[OFFSET(250)] AS p25,
      APPROX_QUANTILES(hypotensive_hours, 1000)[OFFSET(500)] AS p50,
      APPROX_QUANTILES(hypotensive_hours, 1000)[OFFSET(750)] AS p75,
      APPROX_QUANTILES(hypotensive_hours, 1000)[OFFSET(900)] AS p90
    FROM final_stats
    GROUP BY group_label
  )
  UNPIVOT (value FOR percentile IN (p25, p50, p75, p90))
  UNION ALL
  SELECT
    'tachycardic_hours' AS metric,
    percentile,
    value,
    group_label
  FROM (
    SELECT
      group_label,
      APPROX_QUANTILES(tachycardic_hours, 1000)[OFFSET(250)] AS p25,
      APPROX_QUANTILES(tachycardic_hours, 1000)[OFFSET(500)] AS p50,
      APPROX_QUANTILES(tachycardic_hours, 1000)[OFFSET(750)] AS p75,
      APPROX_QUANTILES(tachycardic_hours, 1000)[OFFSET(900)] AS p90
    FROM final_stats
    GROUP BY group_label
  )
  UNPIVOT (value FOR percentile IN (p25, p50, p75, p90))
  UNION ALL
  SELECT
    'icu_los_days' AS metric,
    percentile,
    value,
    group_label
  FROM (
    SELECT
      group_label,
      APPROX_QUANTILES(icu_los_days, 1000)[OFFSET(250)] AS p25,
      APPROX_QUANTILES(icu_los_days, 1000)[OFFSET(500)] AS p50,
      APPROX_QUANTILES(icu_los_days, 1000)[OFFSET(750)] AS p75,
      APPROX_QUANTILES(icu_los_days, 1000)[OFFSET(900)] AS p90
    FROM final_stats
    GROUP BY group_label
  )
  UNPIVOT (value FOR percentile IN (p25, p50, p75, p90))
  UNION ALL
  SELECT
    'mortality_rate' AS metric,
    'rate' AS percentile,
    AVG(hospital_expire_flag) AS value,
    group_label
  FROM final_stats
  GROUP BY group_label
)
SELECT * FROM part1
UNION ALL
SELECT * FROM part2
ORDER BY metric, 
  CASE percentile 
    WHEN 'p25' THEN 1 
    WHEN 'p50' THEN 2 
    WHEN 'p75' THEN 3 
    WHEN 'p90' THEN 4 
    ELSE 5 
  END,
  group_label;