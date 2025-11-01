WITH cohort_stays AS (
  SELECT 
    ie.subject_id, 
    ie.stay_id, 
    ie.hadm_id, 
    ie.los,
    adm.hospital_expire_flag,
    MIN(pe.starttime) AS intubation_time  -- First intubation per ICU stay
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm 
    ON ie.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
    ON ie.stay_id = pe.stay_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 75 AND 85
    AND pe.itemid = 227194  -- Invasive mechanical ventilation (Intubation)
  GROUP BY ie.subject_id, ie.stay_id, ie.hadm_id, ie.los, adm.hospital_expire_flag
),

vital_events AS (
  SELECT 
    cs.stay_id,
    -- Count SBP < 90 events
    COUNTIF(ce.itemid = 220179 AND ce.valuenum < 90) AS hypotension_count,
    -- Count HR > 100 events
    COUNTIF(ce.itemid = 220045 AND ce.valuenum > 100) AS tachycardia_count
  FROM cohort_stays cs
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON cs.stay_id = ce.stay_id
    AND ce.charttime 
      BETWEEN cs.intubation_time 
      AND DATETIME_ADD(cs.intubation_time, INTERVAL 48 HOUR)
    AND ce.itemid IN (220179, 220045)  -- SBP and HR items
  GROUP BY cs.stay_id
),

cohort_scores AS (
  SELECT 
    cs.*,
    COALESCE(ve.hypotension_count, 0) AS hypotension_count,
    COALESCE(ve.tachycardia_count, 0) AS tachycardia_count,
    COALESCE(ve.hypotension_count, 0) + COALESCE(ve.tachycardia_count, 0) AS composite_score
  FROM cohort_stays cs
  LEFT JOIN vital_events ve 
    ON cs.stay_id = ve.stay_id
),

percentiles AS (
  SELECT 
    PERCENTILE_CONT(composite_score, 0.9) OVER() AS p90,
    PERCENTILE_CONT(composite_score, 0.75) OVER() AS p75
  FROM cohort_scores
  LIMIT 1
),

top_25pct AS (
  SELECT 
    cs.*,
    p.p90,
    p.p75
  FROM cohort_scores cs
  CROSS JOIN percentiles p
  WHERE cs.composite_score >= p.p75
)

SELECT 
  (SELECT p90 FROM percentiles) AS ninetieth_percentile_score,
  COUNT(*) AS top25_patient_count,
  -- Proportion with ≥1 hypotension event
  COUNTIF(hypotension_count > 0) / COUNT(*) AS proportion_hypotension,
  -- Proportion with ≥1 tachycardia event
  COUNTIF(tachycardia_count > 0) / COUNT(*) AS proportion_tachycardia,
  -- ICU LOS: Median and IQR
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_icu_los,
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS q1_icu_los,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS q3_icu_los,
  -- Mortality rate
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM top_25pct;