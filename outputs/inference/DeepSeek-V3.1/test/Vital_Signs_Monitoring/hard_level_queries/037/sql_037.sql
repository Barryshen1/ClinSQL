WITH hf_patients AS (
  -- Male ICU patients aged 45-55 with heart failure
  SELECT DISTINCT ie.subject_id, ie.hadm_id, ie.stay_id, ie.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON ie.hadm_id = diag.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '428%') OR
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
    )
),
instability_events AS (
  -- Extract instability events in first 72 hours
  SELECT 
    ie.stay_id,
    ce.charttime,
    CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1 ELSE 0 END AS tachycardia,
    CASE WHEN ce.itemid = 220181 AND ce.valuenum < 65 THEN 1 ELSE 0 END AS hypotension,
    CASE WHEN ce.itemid = 220210 AND ce.valuenum > 20 THEN 1 ELSE 0 END AS tachypnea
  FROM hf_patients ie
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
      AND ce.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 72 HOUR)
  WHERE ce.itemid IN (220045, 220181, 220210)
    AND ce.valuenum IS NOT NULL
),
composite_scores AS (
  -- Calculate composite instability score per patient
  SELECT 
    stay_id,
    SUM(tachycardia) + SUM(hypotension) + SUM(tachypnea) AS comp_score
  FROM instability_events
  GROUP BY stay_id
),
percentile_99 AS (
  -- Get 99th percentile of composite score
  SELECT 
    APPROX_QUANTILES(comp_score, 100) [ORDINAL(99)] AS p99
  FROM composite_scores
),
unstable_quartile AS (
  -- Identify top quartile (most unstable)
  SELECT 
    stay_id,
    comp_score,
    NTILE(4) OVER (ORDER BY comp_score DESC) AS quartile
  FROM composite_scores
),
metrics_hf_unstable AS (
  -- For unstable quartile, compute averages
  SELECT 
    uq.stay_id,
    AVG(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS prop_tachycardia,
    AVG(CASE WHEN ce.itemid = 220181 AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS prop_hypotension,
    AVG(CASE WHEN ce.itemid = 220210 AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS prop_tachypnea,
    ie.los,
    adm.hospital_expire_flag
  FROM unstable_quartile uq
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON uq.stay_id = ie.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON ie.hadm_id = adm.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
      AND ce.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 72 HOUR)
      AND ce.itemid IN (220045, 220181, 220210)
      AND ce.valuenum IS NOT NULL
  WHERE uq.quartile = 1
  GROUP BY uq.stay_id, ie.los, adm.hospital_expire_flag
),
icu_population AS (
  -- All male ICU patients aged 45-55
  SELECT DISTINCT ie.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
),
metrics_icu_pop AS (
  -- For ICU population, compute same metrics
  SELECT 
    ie.stay_id,
    AVG(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS prop_tachycardia,
    AVG(CASE WHEN ce.itemid = 220181 AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS prop_hypotension,
    AVG(CASE WHEN ce.itemid = 220210 AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS prop_tachypnea,
    ie.los,
    adm.hospital_expire_flag
  FROM icu_population pop
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON pop.stay_id = ie.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON ie.hadm_id = adm.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
      AND ce.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 72 HOUR)
      AND ce.itemid IN (220045, 220181, 220210)
      AND ce.valuenum IS NOT NULL
  GROUP BY ie.stay_id, ie.los, adm.hospital_expire_flag
)
-- Final output: compare unstable quartile to ICU population
SELECT 
  'Unstable Quartile' AS cohort,
  COUNT(*) AS n_stays,
  AVG(prop_tachycardia) AS avg_tachycardia,
  AVG(prop_hypotension) AS avg_hypotension,
  AVG(prop_tachypnea) AS avg_tachypnea,
  AVG(los) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM metrics_hf_unstable
UNION ALL
SELECT 
  'ICU Population' AS cohort,
  COUNT(*) AS n_stays,
  AVG(prop_tachycardia) AS avg_tachycardia,
  AVG(prop_hypotension) AS avg_hypotension,
  AVG(prop_tachypnea) AS avg_tachypnea,
  AVG(los) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM metrics_icu_pop;