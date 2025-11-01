WITH cohort AS (
  -- Get ICU stays for females aged 63-73
  SELECT 
    ie.subject_id, 
    ie.hadm_id,  -- Fixed syntax error here
    ie.stay_id,
    ie.intime, 
    ie.outtime,
    ie.los,
    adm.hospital_expire_flag,
    -- Flag for status epilepticus
    MAX(CASE WHEN diag.icd_code = 'G41.901' AND diag.icd_version = 10 THEN 1 ELSE 0 END) AS status_epilepticus
  FROM `physionet-data.mimiciv_3_1_icu`.icustays ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients pat
    ON ie.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions adm
    ON ie.hadm_id = adm.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diag
    ON ie.hadm_id = diag.hadm_id
      AND diag.icd_code = 'G41.901' 
      AND diag.icd_version = 10
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 63 AND 73
  GROUP BY ie.subject_id, ie.hadm_id, ie.stay_id, ie.intime, ie.outtime, ie.los, adm.hospital_expire_flag
),

vitals AS (
  -- Extract vital signs within first 72h of ICU stay
  SELECT 
    co.subject_id,
    co.stay_id,
    ce.charttime,
    -- Heart Rate
    MAX(CASE WHEN ce.itemid = 220045 THEN ce.valuenum ELSE NULL END) AS hr,
    -- Systolic BP
    MAX(CASE WHEN ce.itemid IN (220179, 220050) THEN ce.valuenum ELSE NULL END) AS sbp,
    -- Diastolic BP
    MAX(CASE WHEN ce.itemid IN (220180, 220051) THEN ce.valuenum ELSE NULL END) AS dbp,
    -- Mean Arterial Pressure
    MAX(CASE WHEN ce.itemid IN (220181, 220052) THEN ce.valuenum ELSE NULL END) AS map,
    -- Respiratory Rate
    MAX(CASE WHEN ce.itemid IN (220210, 224690) THEN ce.valuenum ELSE NULL END) AS rr,
    -- SpO2
    MAX(CASE WHEN ce.itemid = 220277 THEN ce.valuenum ELSE NULL END) AS spo2
  FROM cohort co
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce
    ON co.stay_id = ce.stay_id
      AND ce.charttime >= co.intime
      AND ce.charttime <= DATETIME_ADD(co.intime, INTERVAL 72 HOUR)
  WHERE ce.itemid IN (220045, 220179, 220050, 220180, 220051, 220181, 220052, 220210, 224690, 220277)
    AND ce.valuenum IS NOT NULL
  GROUP BY co.subject_id, co.stay_id, ce.charttime
),

vitals_processed AS (
  -- Compute VII and flags per charttime
  SELECT 
    subject_id,
    stay_id,
    charttime,
    -- VII calculation: sum of abnormalities (simplified per clinical question)
    CASE WHEN hr > 100 OR hr < 50 THEN 1 ELSE 0 END
    + CASE WHEN sbp > 180 OR sbp < 90 THEN 1 ELSE 0 END
    + CASE WHEN map < 65 THEN 1 ELSE 0 END
    + CASE WHEN rr > 20 OR rr < 10 THEN 1 ELSE 0 END
    + CASE WHEN spo2 < 90 THEN 1 ELSE 0 END AS vii,
    -- Tachycardia flag
    CASE WHEN hr > 100 THEN 1 ELSE 0 END AS tachycardia,
    -- Hypotension flag
    CASE WHEN map < 65 THEN 1 ELSE 0 END AS hypotension
  FROM vitals
),

agg_metrics AS (
  -- Aggregate per patient
  SELECT 
    v.stay_id,
    AVG(v.vii) AS mean_vii,
    AVG(v.tachycardia) * 100 AS tachycardia_burden_pct,
    AVG(v.hypotension) * 100 AS map_lt65_burden_pct,
    COUNT(*) AS num_measurements
  FROM vitals_processed v
  GROUP BY v.stay_id
),

combined AS (
  -- Combine with cohort and metrics
  SELECT 
    co.subject_id,
    co.stay_id,
    co.status_epilepticus,
    am.mean_vii,
    am.tachycardia_burden_pct,
    am.map_lt65_burden_pct,
    co.los AS icu_los,
    co.hospital_expire_flag AS mortality
  FROM cohort co
  LEFT JOIN agg_metrics am
    ON co.stay_id = am.stay_id
  WHERE am.num_measurements > 0  -- Exclude patients with no vitals
)

-- Calculate statistics for case and control groups
SELECT 
  CASE WHEN status_epilepticus = 1 THEN 'Status Epilepticus' ELSE 'General ICU' END AS group_name,
  COUNT(*) AS n_patients,
  AVG(mean_vii) AS mean_vii,
  APPROX_QUANTILES(mean_vii, 4)[OFFSET(1)] AS p25_vii,
  APPROX_QUANTILES(mean_vii, 4)[OFFSET(2)] AS p50_vii,
  APPROX_QUANTILES(mean_vii, 4)[OFFSET(3)] AS p75_vii,
  APPROX_QUANTILES(mean_vii, 10)[OFFSET(9)] AS p90_vii,
  AVG(tachycardia_burden_pct) AS mean_tachycardia_burden,
  AVG(map_lt65_burden_pct) AS mean_map_lt65_burden,
  AVG(icu_los) AS mean_icu_los,
  AVG(mortality) * 100 AS mortality_percent
FROM combined
GROUP BY group_name
ORDER BY group_name;