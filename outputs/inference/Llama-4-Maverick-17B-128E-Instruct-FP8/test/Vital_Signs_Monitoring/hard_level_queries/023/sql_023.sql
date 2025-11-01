WITH 
-- Step 1: Identify the cohort
cohort AS (
  SELECT 
    p.subject_id, 
    ie.hadm_id, 
    ie.stay_id, 
    p.anchor_age,
    ie.intime,
    ie.outtime,
    CASE WHEN p.anchor_age BETWEEN 55 AND 65 AND p.gender = 'M' THEN 1 ELSE 0 END AS age_gender_match
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ie ON p.subject_id = ie.subject_id
),

-- Step 2: Identify HFNC within 24 hours
hfnc_patients AS (
  SELECT DISTINCT 
    c.stay_id
  FROM 
    cohort c
  JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON c.stay_id = ce.stay_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE 
    di.label LIKE '%High Flow%' AND 
    ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
),

-- Step 3 & 4: Calculate required metrics
metrics AS (
  SELECT 
    c.stay_id,
    c.age_gender_match,
    CASE WHEN hp.stay_id IS NOT NULL THEN 1 ELSE 0 END AS hfnc_group,
    -- ICU LOS
    TIMESTAMP_DIFF(c.outtime, c.intime, HOUR) AS icu_los,
    -- Tachycardia and hypotension burden (example for heart rate > 100)
    (SELECT COUNT(*) FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce 
     JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
     WHERE ce.stay_id = c.stay_id AND di.label LIKE '%Heart Rate%' AND ce.valuenum > 100) AS tachycardia_count,
    -- Mortality (simplified, assuming hospital_expire_flag indicates mortality)
    (SELECT hospital_expire_flag FROM `physionet-data.mimiciv_3_1_hosp.admissions` a WHERE a.hadm_id = c.hadm_id) AS mortality
  FROM 
    cohort c
  LEFT JOIN 
    hfnc_patients hp ON c.stay_id = hp.stay_id
),

-- Aggregate metrics by hfnc_group
aggregated_metrics AS (
  SELECT 
    hfnc_group,
    APPROX_QUANTILES(icu_los, 100)[OFFSET(50)] AS median_icu_los,
    APPROX_QUANTILES(icu_los, 100)[OFFSET(25)] AS p25_icu_los,
    APPROX_QUANTILES(icu_los, 100)[OFFSET(75)] AS p75_icu_los,
    APPROX_QUANTILES(icu_los, 100)[OFFSET(95)] AS p95_icu_los,
    AVG(tachycardia_count) AS avg_tachycardia_burden,
    AVG(mortality) AS avg_mortality,
    COUNT(*) AS count_stays
  FROM 
    metrics
  WHERE 
    age_gender_match = 1
  GROUP BY 
    hfnc_group
)

-- Final selection
SELECT 
  hfnc_group,
  median_icu_los,
  p25_icu_los,
  p75_icu_los,
  p95_icu_los,
  avg_tachycardia_burden,
  avg_mortality,
  count_stays
FROM 
  aggregated_metrics;