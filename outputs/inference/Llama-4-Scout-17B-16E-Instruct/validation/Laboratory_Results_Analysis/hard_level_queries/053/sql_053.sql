WITH 
-- Define target population
target_population AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE 
    p.gender = 'M' AND 
    p.anchor_age BETWEEN 68 AND 78
),

-- Admissions for target population
target_admissions AS (
  SELECT 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.deathtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    target_population tp ON a.subject_id = tp.subject_id
),

-- Lab events for target population
lab_events_target AS (
  SELECT 
    le.hadm_id, 
    le.itemid, 
    le.charttime, 
    le.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN 
    target_admissions ta ON le.hadm_id = ta.hadm_id
  WHERE 
    le.itemid IN (
      -- IDs for Cr, K, platelets, Hgb, WBC
      220050,  -- Creatinine
      220179,  -- Potassium
      220051,  -- Platelets
      220052,  -- Hemoglobin
      220179  -- Serum Potassium; Note: Whole-blood K itemid might differ
    )
),

-- Calculate lab-instability score (example: standard deviation of values over 72h)
lab_instability AS (
  SELECT 
    hadm_id, 
    STDDEV(valuenum) AS instability_score
  FROM 
    lab_events_target
  GROUP BY 
    hadm_id
),

-- Calculate 90th percentile of instability_score
percentile_score AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 0.9)[OFFSET(1)] AS percentile_90
  FROM 
    lab_instability
),

-- Identify top-tier patients (90th percentile of lab-instability score)
top_tier_patients AS (
  SELECT 
    hadm_id
  FROM 
    lab_instability
  WHERE 
    instability_score >= (SELECT percentile_90 FROM percentile_score)
),

-- Critical lab rates for top-tier patients
top_tier_lab_rates AS (
  SELECT 
    hadm_id,
    AVG(CASE WHEN itemid = 220050 THEN valuenum END) AS avg_cr,
    AVG(CASE WHEN itemid = 220179 THEN valuenum END) AS avg_k,
    AVG(CASE WHEN itemid = 220051 THEN valuenum END) AS avg_platelets,
    AVG(CASE WHEN itemid = 220052 THEN valuenum END) AS avg_hgb,
    AVG(CASE WHEN itemid = 220050_1 THEN valuenum END) AS avg_wb_k  -- Assuming a different itemid for whole-blood K
  FROM 
    lab_events_target
  WHERE 
    hadm_id IN (SELECT hadm_id FROM top_tier_patients)
  GROUP BY 
    hadm_id
)

-- Final query for top-tier patients' outcomes
SELECT 
  -- Mortality
  SUM(CASE WHEN ta.hospital_expire_flag = 1 OR ta.deathtime IS NOT NULL THEN 1 ELSE 0 END) AS mortality_count,
  COUNT(DISTINCT ta.hadm_id) AS total_patients,
  -- Average LOS
  AVG(DATE_DIFF(ta.dischtime, ta.admittime)) AS avg_los,
  -- Critical rates (example for Cr, adjust for others)
  AVG(ttlr.avg_cr) AS avg_cr,
  AVG(ttlr.avg_k) AS avg_k,
  AVG(ttlr.avg_platelets) AS avg_platelets,
  AVG(ttlr.avg_hgb) AS avg_hgb,
  AVG(ttlr.avg_wb_k) AS avg_wb_k
FROM 
  target_admissions ta
  JOIN top_tier_patients ttp ON ta.hadm_id = ttp.hadm_id
  LEFT JOIN top_tier_lab_rates ttlr ON ta.hadm_id = ttlr.hadm_id;