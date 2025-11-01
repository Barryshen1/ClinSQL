WITH first_stays AS (
  -- Compute first ICU stay ranking
  SELECT 
    subject_id,
    stay_id,
    hadm_id,
    intime,
    outtime,
    los
  FROM (
    SELECT 
      subject_id,
      stay_id,
      hadm_id,
      intime,
      outtime,
      los,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  )
  WHERE rn = 1
),
cohort AS (
  -- Base cohort: first ICU stay, females, age 58-68 for subgroup
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    fs.stay_id,
    fs.hadm_id,
    fs.intime,
    fs.outtime,
    fs.los,
    a.hospital_expire_flag,
    CASE WHEN p.anchor_age BETWEEN 58 AND 68 THEN 1 ELSE 0 END AS is_subgroup
  FROM first_stays fs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON fs.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON fs.hadm_id = a.hadm_id
  WHERE p.gender = 'F'  -- All females for subgroup and comparison
),
rrt_cohort AS (
  -- Confirm RRT: any input or procedure event with RRT itemids during stay
  SELECT 
    c.*,
    1 AS on_rrt
  FROM cohort c
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
    WHERE ie.stay_id = c.stay_id
      AND ie.itemid IN (225798, 225800, 225908, 225910, 225956, 225958, 227322, 227333, 227334, 227335, 227336, 227337, 227338, 227339, 227340, 227341, 227342, 227343, 227344, 227345, 227346, 227347, 227348, 227349, 227350, 227351)
      AND ie.amount > 0  -- Non-zero RRT fluid input
      AND c.intime <= ie.starttime 
      AND ie.starttime < TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
    UNION DISTINCT
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    WHERE pe.stay_id = c.stay_id
      AND pe.itemid = 225477  -- RRT procedure
      AND c.intime <= pe.starttime 
      AND pe.starttime < TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
  )
),
hourly_vitals AS (
  -- Hourly avg MAP and HR in first 72h
  SELECT 
    rc.stay_id,
    rc.is_subgroup,
    DATE_TRUNC(charttime, HOUR) AS hour_start,
    AVG(CASE WHEN ce.itemid = 220052 THEN valuenum END) AS avg_map,  -- MAP
    AVG(CASE WHEN ce.itemid = 220045 THEN valuenum END) AS avg_hr    -- HR
  FROM rrt_cohort rc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON rc.stay_id = ce.stay_id 
    AND ce.itemid IN (220052, 220045)
    AND rc.intime <= ce.charttime 
    AND ce.charttime < TIMESTAMP_ADD(rc.intime, INTERVAL 72 HOUR)
    AND valuenum IS NOT NULL
  GROUP BY stay_id, is_subgroup, hour_start
),
instability_metrics AS (
  -- Compute instability index (avg concurrent hypotensive+tachycardic hours), hypotensive hours, tachycardic hours
  SELECT 
    stay_id,
    is_subgroup,
    COUNT(*) AS total_hours,
    SUM(CASE WHEN avg_map < 65 AND avg_hr > 100 THEN 1 ELSE 0 END) AS concurrent_unstable_hours,
    SAFE_DIVIDE(SUM(CASE WHEN avg_map < 65 AND avg_hr > 100 THEN 1 ELSE 0 END), GREATEST(COUNT(*), 1)) * LEAST(COUNT(*), 72) AS instability_index,  -- Normalized avg over observed hours, capped at 72
    SUM(CASE WHEN avg_map < 65 THEN 1 ELSE 0 END) AS hypotensive_hours,
    SUM(CASE WHEN avg_hr > 100 THEN 1 ELSE 0 END) AS tachycardic_hours
  FROM hourly_vitals
  GROUP BY stay_id, is_subgroup
  HAVING total_hours > 0  -- Exclude stays with no vitals
),
final_metrics AS (
  -- Join back to cohort for LOS, mortality
  SELECT 
    im.stay_id,
    im.is_subgroup,
    im.instability_index,
    im.concurrent_unstable_hours,
    im.hypotensive_hours,
    im.tachycardic_hours,
    rc.los,
    rc.hospital_expire_flag
  FROM instability_metrics im
  INNER JOIN rrt_cohort rc ON im.stay_id = rc.stay_id
)
-- Aggregates: For subgroup (is_subgroup=1), percentiles/IQR; for others (is_subgroup=0), same for comparison
SELECT 
  'Subgroup (58-68yo females on RRT)' AS group_type,
  is_subgroup,
  SAFE_APPROX_QUANTILES(instability_index, 4)[OFFSET(1)] AS p25_instability,
  SAFE_APPROX_QUANTILES(instability_index, 4)[OFFSET(2)] AS p50_instability,
  SAFE_APPROX_QUANTILES(instability_index, 4)[OFFSET(3)] AS p75_instability,
  SAFE_APPROX_QUANTILES(instability_index, 10)[OFFSET(9)] AS p90_instability,
  SAFE_APPROX_QUANTILES(hypotensive_hours, 4)[OFFSET(1)] AS p25_hypo_hours,
  SAFE_APPROX_QUANTILES(hypotensive_hours, 4)[OFFSET(2)] AS p50_hypo_hours,
  SAFE_APPROX_QUANTILES(hypotensive_hours, 4)[OFFSET(3)] AS p75_hypo_hours,
  SAFE_APPROX_QUANTILES(tachycardic_hours, 4)[OFFSET(1)] AS p25_tachy_hours,
  SAFE_APPROX_QUANTILES(tachycardic_hours, 4)[OFFSET(2)] AS p50_tachy_hours,
  SAFE_APPROX_QUANTILES(tachycardic_hours, 4)[OFFSET(3)] AS p75_tachy_hours,
  SAFE_APPROX_QUANTILES(los, 4)[OFFSET(2)] AS median_los,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) * 100 AS mortality_pct,
  COUNT(*) AS n_patients
FROM final_metrics
WHERE is_subgroup = 1
GROUP BY is_subgroup

UNION ALL

SELECT 
  'Other RRT patients' AS group_type,
  is_subgroup,
  SAFE_APPROX_QUANTILES(instability_index, 4)[OFFSET(1)] AS p25_instability,
  SAFE_APPROX_QUANTILES(instability_index, 4)[OFFSET(2)] AS p50_instability,
  SAFE_APPROX_QUANTILES(instability_index, 4)[OFFSET(3)] AS p75_instability,
  SAFE_APPROX_QUANTILES(instability_index, 10)[OFFSET(9)] AS p90_instability,
  SAFE_APPROX_QUANTILES(hypotensive_hours, 4)[OFFSET(1)] AS p25_hypo_hours,
  SAFE_APPROX_QUANTILES(hypotensive_hours, 4)[OFFSET(2)] AS p50_hypo_hours,
  SAFE_APPROX_QUANTILES(hypotensive_hours, 4)[OFFSET(3)] AS p75_hypo_hours,
  SAFE_APPROX_QUANTILES(tachycardic_hours, 4)[OFFSET(1)] AS p25_tachy_hours,
  SAFE_APPROX_QUANTILES(tachycardic_hours, 4)[OFFSET(2)] AS p50_tachy_hours,
  SAFE_APPROX_QUANTILES(tachycardic_hours, 4)[OFFSET(3)] AS p75_tachy_hours,
  SAFE_APPROX_QUANTILES(los, 4)[OFFSET(2)] AS median_los,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) * 100 AS mortality_pct,
  COUNT(*) AS n_patients
FROM final_metrics
WHERE is_subgroup = 0
GROUP BY is_subgroup
ORDER BY group_type;