WITH first_icu_stays AS (
  -- Select first ICU stay per patient
  SELECT 
    subject_id, stay_id, hadm_id, intime, outtime, los,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE los > 0
),
eligible_patients AS (
  -- Base cohort: males 40-50 with first ICU stay
  SELECT 
    p.subject_id, fis.stay_id, fis.hadm_id, fis.intime, fis.outtime, fis.los,
    a.hospital_expire_flag,
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.hadm_id = fis.hadm_id AND di.icd_code LIKE 'J96%'
    ) THEN 1 ELSE 0 END AS resp_failure
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN first_icu_stays fis ON p.subject_id = fis.subject_id AND fis.rn = 1
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON fis.hadm_id = a.hadm_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 40 AND 50
),
vital_events AS (
  -- Extract relevant vitals in first 48h
  SELECT 
    ep.subject_id, ep.stay_id, ep.intime, ep.resp_failure,
    ce.charttime,
    -- HR
    MAX(CASE WHEN ce.itemid IN (211, 220045) THEN ce.valuenum END) AS hr,
    -- Systolic BP
    MAX(CASE WHEN ce.itemid IN (220179) THEN ce.valuenum END) AS sys_bp,
    -- Diastolic BP
    MAX(CASE WHEN ce.itemid IN (220180) THEN ce.valuenum END) AS dia_bp,
    -- MAP (direct)
    MAX(CASE WHEN ce.itemid = 220052 THEN ce.valuenum END) AS map_direct,
    -- RR
    MAX(CASE WHEN ce.itemid IN (618, 220210) THEN ce.valuenum END) AS rr,
    -- SpO2
    MAX(CASE WHEN ce.itemid = 220277 THEN ce.valuenum END) AS spo2
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON ep.stay_id = ce.stay_id
    AND ce.charttime >= ep.intime 
    AND ce.charttime <= ep.intime + INTERVAL 48 HOUR
    AND ce.valuenum IS NOT NULL
  WHERE ce.itemid IN (211, 220045, 220052, 220179, 220180, 618, 220210, 220277)
    AND ( -- Valid ranges
      (ce.itemid IN (211, 220045) AND ce.valuenum BETWEEN 30 AND 200) OR
      (ce.itemid = 220052 AND ce.valuenum BETWEEN 20 AND 150) OR
      (ce.itemid IN (220179, 220180) AND ce.valuenum BETWEEN 20 AND 300) OR
      (ce.itemid IN (618, 220210) AND ce.valuenum BETWEEN 5 AND 60) OR
      (ce.itemid = 220277 AND ce.valuenum BETWEEN 50 AND 100)
    )
  GROUP BY ep.subject_id, ep.stay_id, ep.intime, ep.resp_failure, ce.charttime
),
hourly_buckets AS (
  -- Hourly aggregates and compute MAP (prefer direct, else derived)
  SELECT 
    subject_id, stay_id, resp_failure, intime,
    DATE_TRUNC(charttime, HOUR) AS hour_bucket,
    AVG(hr) AS mean_hr,
    COALESCE(
      AVG(map_direct), 
      (AVG(sys_bp) + 2 * AVG(dia_bp)) / 3
    ) AS mean_map,
    AVG(rr) AS mean_rr,
    AVG(spo2) AS mean_spo2
  FROM vital_events
  GROUP BY subject_id, stay_id, resp_failure, intime, hour_bucket
),
hourly_vii AS (
  -- Compute hourly VII (0-4 scale)
  SELECT 
    *,
    CAST((COALESCE(mean_hr, 0) < 50 OR COALESCE(mean_hr, 0) > 120) AS INT64) + 
    CAST((COALESCE(mean_map, 0) < 65) AS INT64) + 
    CAST((COALESCE(mean_rr, 0) > 30) AS INT64) + 
    CAST((COALESCE(mean_spo2, 0) < 90) AS INT64) AS vii_hourly
  FROM hourly_buckets
),
patient_metrics AS (
  -- Per-patient aggregates
  SELECT 
    ep.subject_id, ep.stay_id, ep.resp_failure, ep.los, ep.hospital_expire_flag,
    AVG(hv.vii_hourly) AS vii_overall,  -- Mean VII over 48h
    -- Burdens (% hours abnormal)
    AVG(CASE WHEN hv.mean_map < 65 THEN 1.0 ELSE 0 END) * 100 AS hypo_burden_pct,
    AVG(CASE WHEN hv.mean_hr > 100 THEN 1.0 ELSE 0 END) * 100 AS tachy_burden_pct
  FROM eligible_patients ep
  INNER JOIN hourly_vii hv ON ep.subject_id = hv.subject_id AND ep.stay_id = hv.stay_id
  GROUP BY ep.subject_id, ep.stay_id, ep.resp_failure, ep.los, ep.hospital_expire_flag
),
summary_stats AS (
  -- Compute stats by group
  SELECT 
    resp_failure,
    COUNT(*) AS n_patients,
    -- VII
    STDDEV(vii_overall) AS vii_sd,
    PERCENTILE_CONT(vii_overall, 0.25) OVER (PARTITION BY resp_failure) AS vii_p25,
    PERCENTILE_CONT(vii_overall, 0.50) OVER (PARTITION BY resp_failure) AS vii_p50,
    PERCENTILE_CONT(vii_overall, 0.75) OVER (PARTITION BY resp_failure) AS vii_p75,
    PERCENTILE_CONT(vii_overall, 0.95) OVER (PARTITION BY resp_failure) AS vii_p95,
    -- Burdens
    STDDEV(hypo_burden_pct) OVER (PARTITION BY resp_failure) AS hypo_sd,
    PERCENTILE_CONT(hypo_burden_pct, 0.25) OVER (PARTITION BY resp_failure) AS hypo_p25,
    PERCENTILE_CONT(hypo_burden_pct, 0.50) OVER (PARTITION BY resp_failure) AS hypo_p50,
    PERCENTILE_CONT(hypo_burden_pct, 0.75) OVER (PARTITION BY resp_failure) AS hypo_p75,
    PERCENTILE_CONT(hypo_burden_pct, 0.95) OVER (PARTITION BY resp_failure) AS hypo_p95,
    STDDEV(tachy_burden_pct) OVER (PARTITION BY resp_failure) AS tachy_sd,
    PERCENTILE_CONT(tachy_burden_pct, 0.25) OVER (PARTITION BY resp_failure) AS tachy_p25,
    PERCENTILE_CONT(tachy_burden_pct, 0.50) OVER (PARTITION BY resp_failure) AS tachy_p50,
    PERCENTILE_CONT(tachy_burden_pct, 0.75) OVER (PARTITION BY resp_failure) AS tachy_p75,
    PERCENTILE_CONT(tachy_burden_pct, 0.95) OVER (PARTITION BY resp_failure) AS tachy_p95,
    -- LOS and mortality
    AVG(los) OVER (PARTITION BY resp_failure) AS los_mean,
    PERCENTILE_CONT(los, 0.5) OVER (PARTITION BY resp_failure) AS los_median,
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) OVER (PARTITION BY resp_failure) * 100 AS mortality_pct
  FROM patient_metrics
  GROUP BY resp_failure, subject_id, stay_id, los, hospital_expire_flag, vii_overall, hypo_burden_pct, tachy_burden_pct
)
SELECT 
  CASE WHEN resp_failure = 1 THEN 'With Respiratory Failure' ELSE 'Without Respiratory Failure' END AS group_label,
  COUNT(DISTINCT subject_id) AS n_patients,
  ANY_VALUE(vii_sd) AS vii_sd, 
  ANY_VALUE(vii_p25) AS vii_p25, 
  ANY_VALUE(vii_p50) AS vii_p50, 
  ANY_VALUE(vii_p75) AS vii_p75, 
  ANY_VALUE(vii_p95) AS vii_p95,
  ANY_VALUE(hypo_sd) AS hypo_sd, 
  ANY_VALUE(hypo_p25) AS hypo_p25, 
  ANY_VALUE(hypo_p50) AS hypo_p50, 
  ANY_VALUE(hypo_p75) AS hypo_p75, 
  ANY_VALUE(hypo_p95) AS hypo_p95,
  ANY_VALUE(tachy_sd) AS tachy_sd, 
  ANY_VALUE(tachy_p25) AS tachy_p25, 
  ANY_VALUE(tachy_p50) AS tachy_p50, 
  ANY_VALUE(tachy_p75) AS tachy_p75, 
  ANY_VALUE(tachy_p95) AS tachy_p95,
  ANY_VALUE(los_mean) AS los_mean, 
  ANY_VALUE(los_median) AS los_median, 
  ANY_VALUE(mortality_pct) AS mortality_pct
FROM summary_stats
GROUP BY resp_failure
ORDER BY resp_failure;