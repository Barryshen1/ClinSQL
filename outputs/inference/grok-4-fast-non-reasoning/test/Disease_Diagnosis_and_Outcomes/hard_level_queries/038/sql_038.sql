WITH cohort_base AS (
  -- Base elderly male inpatients
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.dod,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
),

-- AKI identification (KDIGO on creatinine)
creatinine_labs AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum AS creat
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE dli.itemid = 50912  -- Serum Creatinine
    AND le.valuenum IS NOT NULL
),

baseline_creat AS (
  SELECT 
    cb.subject_id,
    cb.hadm_id,
    cb.admittime,
    MIN(cl.creat) AS baseline_creat
  FROM cohort_base cb
  LEFT JOIN creatinine_labs cl
    ON cl.subject_id = cb.subject_id
    AND cl.charttime BETWEEN TIMESTAMP_SUB(cb.admittime, INTERVAL 7 DAY) AND TIMESTAMP_SUB(cb.admittime, INTERVAL 48 HOUR)
  GROUP BY cb.subject_id, cb.hadm_id, cb.admittime
  HAVING baseline_creat IS NOT NULL
),

admission_creat AS (
  SELECT 
    bc.subject_id,
    bc.hadm_id,
    bc.baseline_creat,
    MAX(cl.creat) AS max_adm_creat
  FROM baseline_creat bc
  LEFT JOIN creatinine_labs cl
    ON cl.subject_id = bc.subject_id
    AND cl.hadm_id = bc.hadm_id
    AND cl.charttime BETWEEN bc.admittime AND TIMESTAMP_ADD(bc.admittime, INTERVAL 7 DAY)
  GROUP BY bc.subject_id, bc.hadm_id, bc.baseline_creat
),

aki_cohort AS (
  SELECT 
    cb.*,
    ac.baseline_creat,
    ac.max_adm_creat,
    CASE 
      WHEN ac.max_adm_creat >= ac.baseline_creat * 1.5 THEN 1  -- Stage 1+ (1.5x baseline)
      ELSE 0 
    END AS has_aki
  FROM cohort_base cb
  LEFT JOIN admission_creat ac ON cb.hadm_id = ac.hadm_id
  WHERE ac.baseline_creat IS NOT NULL  -- Only admissions with baseline
    AND (ac.max_adm_creat >= ac.baseline_creat * 1.5)  -- Filter to AKI only
),

-- Simplified APACHE IV risk score (key components; full needs all vars)
icu_stays AS (
  SELECT 
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    AVG(CASE WHEN ce.itemid = 220045 THEN ce.valuenum END) AS mean_hr,  -- Heart rate
    AVG(CASE WHEN ce.itemid = 220179 THEN ce.valuenum END) AS mean_sbp,  -- SBP
    AVG(CASE WHEN ce.itemid = 220210 THEN ce.valuenum END) AS mean_rr,   -- RR
    AVG(CASE WHEN ce.itemid = 223762 THEN ce.valuenum END) AS mean_temp, -- Temp
    MIN(CASE WHEN ce.itemid IN (223900, 223901) THEN ce.valuenum END) AS min_gcs,  -- GCS (simplified)
    AVG(CASE WHEN ce.itemid = 220615 THEN ce.valuenum END) AS mean_wbc,  -- WBC (placeholder for more labs)
    10 AS diag_points  -- Placeholder; map icd_code to APACHE weights in full query
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ic.stay_id = ce.stay_id
    AND ce.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 24 HOUR)
  WHERE ce.itemid IN (220045, 220179, 220210, 223762, 223900, 223901, 220615)  -- Key items
  GROUP BY ic.subject_id, ic.hadm_id, ic.stay_id, ic.intime
),

risk_scores_aki AS (
  SELECT 
    ac.subject_id,
    ac.hadm_id,
    COALESCE(ac.anchor_age * 0.5, 0) +  -- Age points (simplified APACHE weighting)
    (CASE WHEN is.mean_hr > 100 THEN 4 ELSE 0 END) +  -- HR points
    (CASE WHEN is.mean_sbp < 100 THEN 6 ELSE 0 END) +  -- SBP points
    (CASE WHEN is.mean_rr > 30 THEN 8 ELSE 0 END) +   -- RR points
    (CASE WHEN is.mean_temp > 39 THEN 3 ELSE 0 END) + -- Temp points
    (CASE WHEN is.min_gcs < 15 THEN (15 - COALESCE(is.min_gcs, 15)) * 2 ELSE 0 END) +  -- GCS points
    COALESCE(is.diag_points, 0) AS apache_risk  -- Total simplified score (0-100+ range)
  FROM aki_cohort ac
  LEFT JOIN icu_stays is ON ac.subject_id = is.subject_id AND ac.hadm_id = is.hadm_id
),

-- 30-day mortality (for AKI)
mortality_aki AS (
  SELECT 
    ac.subject_id,
    ac.hadm_id,
    CASE 
      WHEN ac.deathtime IS NOT NULL AND ac.deathtime <= TIMESTAMP_ADD(ac.admittime, INTERVAL 30 DAY) THEN 1
      WHEN ac.dod IS NOT NULL AND ac.dod <= TIMESTAMP_ADD(ac.admittime, INTERVAL 30 DAY) AND ac.dod >= ac.admittime THEN 1
      ELSE 0 
    END AS mortality_30d
  FROM aki_cohort ac
),

-- ARDS rate (for AKI)
ards_aki AS (
  SELECT 
    di.subject_id,
    di.hadm_id,
    MAX(CASE WHEN di.icd_code IN ('J80', '5185', '51851', '51852') THEN 1 ELSE 0 END) AS has_ards
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN aki_cohort ac ON di.subject_id = ac.subject_id AND di.hadm_id = ac.hadm_id
  GROUP BY di.subject_id, di.hadm_id
),

-- Survivor LOS (for AKI)
survivor_los_aki AS (
  SELECT 
    ac.subject_id,
    ac.hadm_id,
    DATETIME_DIFF(ac.dischtime, ac.admittime, DAY) AS los_days
  FROM aki_cohort ac
  WHERE ac.hospital_expire_flag = 0
    AND ac.dischtime IS NOT NULL
),

-- Aggregates for AKI cohort
aki_metrics AS (
  SELECT 
    'AKI_Cohort' AS cohort_type,
    APPROX_QUANTILES(rs.apache_risk, 4)[OFFSET(2)] AS median_risk,
    APPROX_QUANTILES(rs.apache_risk, 4)[OFFSET(1)] AS iqr_25,
    APPROX_QUANTILES(rs.apache_risk, 4)[OFFSET(3)] AS iqr_75,
    AVG(m.mortality_30d) AS mortality_30d_rate,
    AVG(COALESCE(a.has_ards, 0)) AS ards_rate,
    APPROX_QUANTILES(s.los_days, 2)[OFFSET(1)] AS median_los_survivors
  FROM mortality_aki m
  INNER JOIN risk_scores_aki rs ON m.subject_id = rs.subject_id AND m.hadm_id = rs.hadm_id
  LEFT JOIN ards_aki a ON m.subject_id = a.subject_id AND m.hadm_id = a.hadm_id
  LEFT JOIN survivor_los_aki s ON m.subject_id = s.subject_id AND m.hadm_id = s.hadm_id
),

-- General cohort (all male 74-84 without AKI filter, then exclude AKI)
general_cohort AS (
  SELECT 
    cb.*,
    ac.baseline_creat,
    ac.max_adm_creat,
    CASE 
      WHEN ac.max_adm_creat >= ac.baseline_creat * 1.5 THEN 1
      ELSE 0 
    END AS has_aki
  FROM cohort_base cb
  LEFT JOIN admission_creat ac ON cb.hadm_id = ac.hadm_id
  WHERE ac.baseline_creat IS NOT NULL  -- Only with baseline for fair comparison
    AND (ac.max_adm_creat < ac.baseline_creat * 1.5)  -- Non-AKI only
),

risk_scores_general AS (
  SELECT 
    gc.subject_id,
    gc.hadm_id,
    COALESCE(gc.anchor_age * 0.5, 0) +  
    (CASE WHEN is.mean_hr > 100 THEN 4 ELSE 0 END) +  
    (CASE WHEN is.mean_sbp < 100 THEN 6 ELSE 0 END) +  
    (CASE WHEN is.mean_rr > 30 THEN 8 ELSE 0 END) +   
    (CASE WHEN is.mean_temp > 39 THEN 3 ELSE 0 END) + 
    (CASE WHEN is.min_gcs < 15 THEN (15 - COALESCE(is.min_gcs, 15)) * 2 ELSE 0 END) +  
    COALESCE(is.diag_points, 0) AS apache_risk  
  FROM general_cohort gc
  LEFT JOIN icu_stays is ON gc.subject_id = is.subject_id AND gc.hadm_id = is.hadm_id
),

-- Mortality for general (non-AKI subset)
mortality_general AS (
  SELECT 
    gc.subject_id,
    gc.hadm_id,
    CASE 
      WHEN gc.deathtime IS NOT NULL AND gc.deathtime <= TIMESTAMP_ADD(gc.admittime, INTERVAL 30 DAY) THEN 1
      WHEN gc.dod IS NOT NULL AND gc.dod <= TIMESTAMP_ADD(gc.admittime, INTERVAL 30 DAY) AND gc.dod >= gc.admittime THEN 1
      ELSE 0 
    END AS mortality_30d
  FROM general_cohort gc
),

-- ARDS for general
ards_general AS (
  SELECT 
    di.subject_id,
    di.hadm_id,
    MAX(CASE WHEN di.icd_code IN ('J80', '5185', '51851', '51852') THEN 1 ELSE 0 END) AS has_ards
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN general_cohort gc ON di.subject_id = gc.subject_id AND di.hadm_id = gc.hadm_id
  GROUP BY di.subject_id, di.hadm_id
),

-- Survivor LOS for general
survivor_los_general AS (
  SELECT 
    gc.subject_id,
    gc.hadm_id,
    DATETIME_DIFF(gc.dischtime, gc.admittime, DAY) AS los_days
  FROM general_cohort gc
  WHERE gc.hospital_expire_flag = 0
    AND gc.dischtime IS NOT NULL
),

-- Aggregates for general cohort
general_metrics AS (
  SELECT 
    'General_Cohort' AS cohort_type,
    APPROX_QUANTILES(rsg.apache_risk, 4)[OFFSET(2)] AS median_risk_general,
    AVG(COALESCE(a.has_ards, 0)) AS ards_rate_general,
    APPROX_QUANTILES(s.los_days, 2)[OFFSET(1)] AS median_los_survivors_general,
    -- Full distribution for percentile calc
    rsg.apache_risk
  FROM mortality_general m
  INNER JOIN risk_scores_general rsg ON m.subject_id = rsg.subject_id AND m.hadm_id = rsg.hadm_id
  LEFT JOIN ards_general a ON m.subject_id = a.subject_id AND m.hadm_id = a.hadm_id
  LEFT JOIN survivor_los_general s ON m.subject_id = s.subject_id AND m.hadm_id = s.hadm_id
)

-- Final output
SELECT 
  am.cohort_type AS cohort,
  am.median_risk,
  FORMAT('%.1f (%.1f - %.1f)', CAST(am.median_risk AS FLOAT64), CAST(am.iqr_25 AS FLOAT64), CAST(am.iqr_75 AS FLOAT64)) AS risk_iqr,
  ROUND(am.mortality_30d_rate * 100, 1) AS aki_mortality_30d_pct,
  ROUND(am.ards_rate * 100, 1) AS aki_ards_rate_pct,
  CAST(am.median_los_survivors AS INT64) AS aki_median_los_days,
  ROUND(gm.ards_rate_general * 100, 1) AS general_ards_rate_pct,
  CAST(gm.median_los_survivors_general AS INT64) AS general_median_los_days,
  -- Percentile: % of general cohort with risk <= AKI median
  ROUND(
    (COUNTIF(gm.apache_risk <= am.median_risk) * 100.0 / COUNT(*)) OVER(), 1
  ) AS aki_risk_percentile_vs_general
FROM aki_metrics am
CROSS JOIN general_metrics gm
GROUP BY am.cohort_type, am.median_risk, am.iqr_25, am.iqr_75, am.mortality_30d_rate, 
         am.ards_rate, am.median_los_survivors, gm.ards_rate_general, gm.median_los_survivors_general;