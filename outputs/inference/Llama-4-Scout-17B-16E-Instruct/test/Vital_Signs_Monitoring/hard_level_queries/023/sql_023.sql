WITH 
-- Patient demographics and ICU stay information
patient_info AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    ic.stay_id,
    ic.hadm_id,
    ic.intime,
    ic.outtime,
    ic.los
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON ic.subject_id = p.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 55 AND 65
),

-- HFNC treatment within 24 hours
hfnc_treatment AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    MAX(CASE WHEN d.label = 'High Flow Nasal Cannula' THEN 1 ELSE 0 END) AS hfnc
  FROM 
    `physionet-data.mimiciv_3_1_icu.inputevents` ie
  JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` d 
      ON ie.itemid = d.itemid
  WHERE 
    ie.starttime BETWEEN 
      (SELECT intime FROM patient_info LIMIT 1) 
      AND (SELECT intime FROM patient_info LIMIT 1) + INTERVAL 24 HOUR
  GROUP BY 
    subject_id, hadm_id, stay_id
),

-- Instability score (using heart rate, blood pressure, and oxygen saturation)
instability_score AS (
  SELECT 
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    -- Simple instability score based on HR, BP, and SpO2
    CASE 
      WHEN ce.valuenum > 100 THEN 1 
      ELSE 0 
    END AS tachycardia,
    CASE 
      WHEN ce.valuenum < 60 THEN 1 
      ELSE 0 
    END AS hypotension,
    CASE 
      WHEN ce.valuenum < 88 THEN 1 
      ELSE 0 
    END AS hypoxemia
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE 
    ce.itemid IN (
      220050,  -- Heart Rate
      220179,  -- Systolic Blood Pressure
      220052   -- Oxygen Saturation
    )
),

-- Calculate median and percentiles of instability score
score_percentiles AS (
  SELECT 
    APPROX_QUANTILES(tachycardia, 1000)[25] AS p25_tachycardia,
    APPROX_QUANTILES(tachycardia, 1000)[500] AS median_tachycardia,
    APPROX_QUANTILES(tachycardia, 1000)[750] AS p75_tachycardia,
    APPROX_QUANTILES(tachycardia, 1000)[950] AS p95_tachycardia,
    APPROX_QUANTILES(hypotension, 1000)[25] AS p25_hypotension,
    APPROX_QUANTILES(hypotension, 1000)[500] AS median_hypotension,
    APPROX_QUANTILES(hypotension, 1000)[750] AS p75_hypotension,
    APPROX_QUANTILES(hypotension, 1000)[950] AS p95_hypotension
  FROM 
    instability_score
),

-- ICU LOS and mortality
icu_outcome AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    los,
    CASE 
      WHEN outtime IS NULL THEN 1 
      ELSE 0 
    END AS mortality
  FROM 
    patient_info
)

-- Final query
SELECT 
  COALESCE(hf.hadm_id, c.hadm_id) AS hadm_id,
  -- Instability score percentiles
  sp.p25_tachycardia,
  sp.median_tachycardia,
  sp.p75_tachycardia,
  sp.p95_tachycardia,
  sp.p25_hypotension,
  sp.median_hypotension,
  sp.p75_hypotension,
  sp.p95_hypotension,
  -- ICU LOS and mortality
  AVG(icu.los) AS icu_los,
  SUM(icu.mortality) / COUNT(icu.mortality) AS mortality_rate
FROM 
  patient_info c
  LEFT JOIN hfnc_treatment hf 
    ON c.subject_id = hf.subject_id AND c.hadm_id = hf.hadm_id AND c.stay_id = hf.stay_id
  CROSS JOIN score_percentiles sp
  LEFT JOIN icu_outcome icu 
    ON c.subject_id = icu.subject_id AND c.hadm_id = icu.hadm_id AND c.stay_id = icu.stay_id
GROUP BY 
  COALESCE(hf.hadm_id, c.hadm_id),
  sp.p25_tachycardia,
  sp.median_tachycardia,
  sp.p75_tachycardia,
  sp.p95_tachycardia,
  sp.p25_hypotension,
  sp.median_hypotension,
  sp.p75_hypotension,
  sp.p95_hypotension;