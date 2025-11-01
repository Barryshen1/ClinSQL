WITH filtered_stays AS (
  -- Base ICU stays with demographics and shock flag
  SELECT 
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pat.gender,
    pat.anchor_age,
    adm.hospital_expire_flag,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        WHERE diag.hadm_id = icu.hadm_id 
          AND (diag.icd_version = SAFE_CAST('10' AS INT64) AND (diag.icd_code LIKE 'R57%' OR diag.icd_code = 'T81.19'))
          OR (diag.icd_version = SAFE_CAST('9' AS INT64) AND diag.icd_code LIKE '785.5%')
      ) THEN 1 ELSE 0 
    END AS with_shock
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 59 AND 69
    AND icu.los >= 1  -- At least 24h observation
),

vitals AS (
  -- Vital signs in first 24h: MAP and HR (using known item IDs to avoid category issues)
  SELECT 
    stay.stay_id,
    stay.intime,
    ce.subject_id,
    ce.hadm_id,
    ce.charttime,
    ce.itemid,
    ce.valuenum,
    FLOOR(TIMESTAMP_DIFF(ce.charttime, stay.intime, HOUR)) AS hour_bucket
  FROM filtered_stays stay
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON stay.stay_id = ce.stay_id
  WHERE ce.charttime >= stay.intime 
    AND ce.charttime < DATETIME_ADD(stay.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL 
    AND ce.valuenum > 0 
    AND ce.valuenum < 300  -- Physiologic range
    AND ce.itemid IN (220052, 220277, 220074, 220045)  -- MAP: mean arterial BP; HR: heart rate (covers common variants)
),

hourly_vitals AS (
  -- Hourly averages for MAP and HR
  SELECT 
    stay_id,
    hour_bucket,
    AVG(CASE WHEN itemid IN (220052, 220277, 220074) THEN valuenum END) AS avg_map,
    AVG(CASE WHEN itemid IN (220045) THEN valuenum END) AS avg_hr
  FROM vitals
  GROUP BY stay_id, hour_bucket
  HAVING hour_bucket >= 0 AND hour_bucket < 24  -- Ensure 0-23
),

burdens AS (
  -- Calculate burdens per stay
  SELECT 
    fs.stay_id,
    fs.with_shock,
    fs.los,
    fs.hospital_expire_flag,
    COUNT(CASE WHEN hv.avg_map < 65 THEN 1 END) * 100.0 / 24 AS hypotension_burden_pct,  -- % hours with MAP<65
    COUNT(CASE WHEN hv.avg_hr > 100 THEN 1 END) * 100.0 / 24 AS tachycardia_burden_pct  -- % hours with HR>100
  FROM filtered_stays fs
  LEFT JOIN hourly_vitals hv ON fs.stay_id = hv.stay_id
  GROUP BY fs.stay_id, fs.with_shock, fs.los, fs.hospital_expire_flag
),

lactate AS (
  -- Any lactate >2 in first 24h
  SELECT 
    stay.stay_id,
    MAX(CASE WHEN le.valuenum > 2 THEN 1 ELSE 0 END) AS high_lactate
  FROM filtered_stays stay
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON stay.subject_id = le.subject_id AND stay.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE le.charttime >= stay.intime 
    AND le.charttime < DATETIME_ADD(stay.intime, INTERVAL 24 HOUR)
    AND le.valuenum IS NOT NULL
    AND LOWER(dli.label) LIKE '%lactate%'
  GROUP BY stay.stay_id
),

instability AS (
  -- Composite score: hypotension >10%, tachycardia >10%, high lactate
  SELECT 
    b.stay_id,
    b.with_shock,
    b.los,
    b.hospital_expire_flag,
    b.hypotension_burden_pct,
    b.tachycardia_burden_pct,
    COALESCE(l.high_lactate, 0) AS high_lactate,
    (CASE WHEN b.hypotension_burden_pct > 10 THEN 1 ELSE 0 END +
     CASE WHEN b.tachycardia_burden_pct > 10 THEN 1 ELSE 0 END +
     COALESCE(l.high_lactate, 0)) AS instability_score
  FROM burdens b
  LEFT JOIN lactate l ON b.stay_id = l.stay_id
),

-- Single aggregation for all metrics to avoid repeated scans
final_agg AS (
  SELECT 
    with_shock,
    AVG(instability_score) AS instability_mean,
    PERCENTILE_CONT(instability_score, 0.25) OVER (PARTITION BY with_shock) AS instability_p25,
    PERCENTILE_CONT(instability_score, 0.50) OVER (PARTITION BY with_shock) AS instability_p50,
    PERCENTILE_CONT(instability_score, 0.75) OVER (PARTITION BY with_shock) AS instability_p75,
    AVG(hypotension_burden_pct) AS hypotension_mean,
    PERCENTILE_CONT(hypotension_burden_pct, 0.25) OVER (PARTITION BY with_shock) AS hypotension_p25,
    PERCENTILE_CONT(hypotension_burden_pct, 0.50) OVER (PARTITION BY with_shock) AS hypotension_p50,
    PERCENTILE_CONT(hypotension_burden_pct, 0.75) OVER (PARTITION BY with_shock) AS hypotension_p75,
    AVG(tachycardia_burden_pct) AS tachycardia_mean,
    PERCENTILE_CONT(tachycardia_burden_pct, 0.25) OVER (PARTITION BY with_shock) AS tachycardia_p25,
    PERCENTILE_CONT(tachycardia_burden_pct, 0.50) OVER (PARTITION BY with_shock) AS tachycardia_p50,
    PERCENTILE_CONT(tachycardia_burden_pct, 0.75) OVER (PARTITION BY with_shock) AS tachycardia_p75,
    AVG(los) AS los_mean,
    PERCENTILE_CONT(los, 0.25) OVER (PARTITION BY with_shock) AS los_p25,
    PERCENTILE_CONT(los, 0.50) OVER (PARTITION BY with_shock) AS los_p50,
    PERCENTILE_CONT(los, 0.75) OVER (PARTITION BY with_shock) AS los_p75,
    AVG(hospital_expire_flag) * 100 AS mortality_mean
  FROM instability
  GROUP BY with_shock
)

-- Pivot to long format for metrics
SELECT with_shock, 'instability_score' AS metric, instability_mean AS mean_value, instability_p25 AS p25, instability_p50 AS p50, instability_p75 AS p75 FROM final_agg
UNION ALL
SELECT with_shock, 'hypotension_burden_pct' AS metric, hypotension_mean AS mean_value, hypotension_p25 AS p25, hypotension_p50 AS p50, hypotension_p75 AS p75 FROM final_agg
UNION ALL
SELECT with_shock, 'tachycardia_burden_pct' AS metric, tachycardia_mean AS mean_value, tachycardia_p25 AS p25, tachycardia_p50 AS p50, tachycardia_p75 AS p75 FROM final_agg
UNION ALL
SELECT with_shock, 'icu_los' AS metric, los_mean AS mean_value, los_p25 AS p25, los_p50 AS p50, los_p75 AS p75 FROM final_agg
UNION ALL
SELECT with_shock, 'mortality' AS metric, mortality_mean AS mean_value, NULL AS p25, NULL AS p50, NULL AS p75 FROM final_agg
ORDER BY with_shock, metric;