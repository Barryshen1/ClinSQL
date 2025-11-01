WITH rrt_stays AS (
  -- Identify all RRT ICU stays, flag subgroup (women 58-68)
  SELECT 
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    icu.intime,
    icu.los,
    pat.gender,
    pat.anchor_age,
    adm.hospital_expire_flag,
    CASE 
      WHEN pat.gender = 'F' AND pat.anchor_age BETWEEN 58 AND 68 THEN 1 
      ELSE 0 
    END AS is_subgroup
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  WHERE EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    WHERE pe.stay_id = icu.stay_id 
      AND pe.itemid IN (228351, 228352)
  )
    -- Optional: filter adults, but age range covers
),
hourly_vitals AS (
  -- Extract HR and MAP in first 72h, avg per hour
  SELECT 
    ce.stay_id,
    TIMESTAMP_DIFF(ce.charttime, rs.intime, HOUR) AS hour_bin,
    ce.itemid,
    AVG(ce.valuenum) AS avg_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN rrt_stays rs
    ON ce.stay_id = rs.stay_id
  WHERE ce.charttime >= rs.intime 
    AND ce.charttime < TIMESTAMP_ADD(rs.intime, INTERVAL 72 HOUR)
    AND ce.itemid IN (220045, 220052)  -- HR, MAP
    AND ce.valuenum IS NOT NULL 
    AND ce.valuenum > 0
  GROUP BY ce.stay_id, hour_bin, ce.itemid
),
hourly_flags AS (
  -- Per hour: compute flags for hypo, tachy, unstable
  SELECT 
    hv.stay_id,
    hv.hour_bin,
    MAX(CASE WHEN hv.itemid = 220052 AND hv.avg_value < 65 THEN 1 ELSE 0 END) AS is_hypotensive,
    MAX(CASE WHEN hv.itemid = 220045 AND hv.avg_value > 100 THEN 1 ELSE 0 END) AS is_tachycardic,
    MAX(CASE WHEN hv.itemid = 220052 AND hv.avg_value < 65 THEN 1 ELSE 0 END) * 
    MAX(CASE WHEN hv.itemid = 220045 AND hv.avg_value > 100 THEN 1 ELSE 0 END) AS is_unstable
  FROM hourly_vitals hv
  GROUP BY hv.stay_id, hv.hour_bin
),
stay_metrics AS (
  -- Aggregate per stay: hours counts, index
  SELECT 
    rs.stay_id,
    rs.is_subgroup,
    rs.los,
    rs.hospital_expire_flag,
    COALESCE(SUM(hf.is_hypotensive), 0) AS hypotensive_hours,
    COALESCE(SUM(hf.is_tachycardic), 0) AS tachycardic_hours,
    COALESCE(SUM(hf.is_unstable), 0) / 72.0 AS instability_index
  FROM rrt_stays rs
  LEFT JOIN hourly_flags hf
    ON rs.stay_id = hf.stay_id
    AND hf.hour_bin BETWEEN 0 AND 71  -- First 72h
  GROUP BY rs.stay_id, rs.is_subgroup, rs.los, rs.hospital_expire_flag
)
-- Compute percentiles for subgroup index, medians/comparisons for both cohorts
SELECT 
  CASE WHEN is_subgroup = 1 THEN 'Subgroup (Women 58-68 RRT)' ELSE 'Other RRT Patients' END AS cohort,
  CASE WHEN is_subgroup = 1 THEN APPROX_QUANTILES(instability_index, 4)[OFFSET(1)] ELSE NULL END AS p25_index,
  CASE WHEN is_subgroup = 1 THEN APPROX_QUANTILES(instability_index, 4)[OFFSET(2)] ELSE NULL END AS p50_index,
  CASE WHEN is_subgroup = 1 THEN APPROX_QUANTILES(instability_index, 4)[OFFSET(3)] ELSE NULL END AS p75_index,
  CASE WHEN is_subgroup = 1 THEN APPROX_QUANTILES(instability_index, 10)[OFFSET(9)] ELSE NULL END AS p90_index,
  CASE WHEN is_subgroup = 1 THEN (APPROX_QUANTILES(instability_index, 4)[OFFSET(3)] - APPROX_QUANTILES(instability_index, 4)[OFFSET(1)]) ELSE NULL END AS iqr_index,
  APPROX_QUANTILES(hypotensive_hours, 2)[OFFSET(1)] AS median_hypo_hours,
  APPROX_QUANTILES(tachycardic_hours, 2)[OFFSET(1)] AS median_tachy_hours,
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM stay_metrics
GROUP BY is_subgroup
ORDER BY CASE WHEN is_subgroup = 1 THEN 1 ELSE 2 END;