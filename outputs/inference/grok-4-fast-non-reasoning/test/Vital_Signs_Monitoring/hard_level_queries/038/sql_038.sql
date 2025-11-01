WITH general_cohort AS (
  -- Female ICU patients aged 63-73, first ICU stay
  SELECT 
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
    AND i.los >= 1.0 / 24.0  -- At least 1 hour
  QUALIFY rn = 1
),

status_cohort AS (
  -- Subset with status epilepticus (ICD-10 G40.911)
  SELECT 
    gc.subject_id,
    gc.stay_id,
    gc.hadm_id,
    gc.intime,
    gc.los,
    gc.hospital_expire_flag
  FROM general_cohort gc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON gc.subject_id = d.subject_id AND gc.hadm_id = d.hadm_id
  WHERE d.icd_code = 'G40.911' AND d.icd_version = '10'
),

vital_events AS (
  -- Vital signs in first 72 hours for both cohorts
  SELECT 
    gc.subject_id,
    gc.stay_id,
    gc.intime,
    ce.charttime,
    ce.itemid,
    ce.valuenum
  FROM general_cohort gc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON gc.subject_id = ce.subject_id 
    AND gc.stay_id = ce.stay_id
    AND ce.itemid IN (220045, 220052, 220277)  -- HR, MAP, SpO2
    AND ce.valuenum IS NOT NULL
    AND ce.charttime > gc.intime
    AND ce.charttime <= TIMESTAMP_ADD(gc.intime, INTERVAL 72 HOUR)
),

-- Add cohort flag (1=status, 0=general)
vitals_flagged AS (
  SELECT 
    ve.*,
    CASE WHEN sc.stay_id IS NOT NULL THEN 1 ELSE 0 END AS is_status
  FROM vital_events ve
  LEFT JOIN status_cohort sc
    ON ve.subject_id = sc.subject_id AND ve.stay_id = sc.stay_id
),

-- Burdens per stay (tachycardia: HR>100; MAP<65; desat: SpO2<92)
burdens AS (
  SELECT 
    subject_id,
    stay_id,
    is_status,
    -- Total monitoring minutes (distinct 5-min intervals with any vital)
    COUNT(DISTINCT TIMESTAMP_TRUNC(charttime, MINUTE) / 5 * 5) * 5 AS total_minutes,
    -- Tachycardia burden (% time)
    SAFE_DIVIDE(COUNTIF(itemid = 220045 AND valuenum > 100), COUNTIF(itemid = 220045)) * 100 AS tach_burden,
    -- MAP<65 burden (% time)
    SAFE_DIVIDE(COUNTIF(itemid = 220052 AND valuenum < 65), COUNTIF(itemid = 220052)) * 100 AS map_low_burden,
    -- Desat burden (% time, for index)
    SAFE_DIVIDE(COUNTIF(itemid = 220277 AND valuenum < 92), COUNTIF(itemid = 220277)) * 100 AS desat_burden
  FROM vitals_flagged
  GROUP BY subject_id, stay_id, is_status
),

-- Vital instability index = sum of three burdens (0-300 scale)
instability_index AS (
  SELECT 
    b.subject_id,
    b.stay_id,
    b.is_status,
    COALESCE(tach_burden, 0) + COALESCE(map_low_burden, 0) + COALESCE(desat_burden, 0) AS instability_idx,
    COALESCE(tach_burden, 0) AS tach_burden,
    COALESCE(map_low_burden, 0) AS map_low_burden,
    gc.los,
    gc.hospital_expire_flag
  FROM burdens b
  INNER JOIN general_cohort gc
    ON b.subject_id = gc.subject_id AND b.stay_id = gc.stay_id
),

-- Aggregates per cohort
cohort_stats AS (
  SELECT 
    is_status AS cohort,  -- 1=status, 0=general
    COUNT(*) AS n_patients,
    -- Instability index stats
    AVG(instability_idx) AS mean_instability_idx,
    PERCENTILE_CONT(instability_idx, 0.25) AS p25_instability_idx,
    PERCENTILE_CONT(instability_idx, 0.50) AS p50_instability_idx,
    PERCENTILE_CONT(instability_idx, 0.75) AS p75_instability_idx,
    PERCENTILE_CONT(instability_idx, 0.90) AS p90_instability_idx,
    -- Tachycardia burden mean
    AVG(tach_burden) AS mean_tach_burden,
    -- MAP<65 burden mean
    AVG(map_low_burden) AS mean_map_low_burden,
    -- LOS mean
    AVG(los) AS mean_los,
    -- Mortality rate
    AVG(CAST(hospital_expire_flag AS FLOAT)) * 100 AS mortality_rate_pct
  FROM instability_index
  GROUP BY is_status
)

SELECT 
  cohort,
  n_patients,
  ROUND(mean_instability_idx, 2) AS mean_instability_idx,
  ROUND(p25_instability_idx, 2) AS p25_instability_idx,
  ROUND(p50_instability_idx, 2) AS p50_instability_idx,
  ROUND(p75_instability_idx, 2) AS p75_instability_idx,
  ROUND(p90_instability_idx, 2) AS p90_instability_idx,
  ROUND(mean_tach_burden, 2) AS mean_tach_burden_pct,
  ROUND(mean_map_low_burden, 2) AS mean_map_low_burden_pct,
  ROUND(mean_los, 2) AS mean_los_days,
  ROUND(mortality_rate_pct, 2) AS mortality_rate_pct
FROM cohort_stats
ORDER BY cohort DESC;  -- Status first;