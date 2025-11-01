WITH 
-- Identify transplant patients
transplant_patients AS (
  SELECT DISTINCT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code LIKE 'V42%'  -- Codes for transplanted organ
),

-- Define vital sign limits
vital_sign_limits AS (
  SELECT 
    itemid,
    label,
    category,
    CASE 
      WHEN label = 'Temperature' THEN 38.5
      WHEN label = 'SpO2' THEN 90
      WHEN label = 'Respiratory Rate' THEN 20
    END AS threshold
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label IN ('Temperature', 'SpO2', 'Respiratory Rate')
),

-- Calculate composite instability score
instability_scores AS (
  SELECT 
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    COUNT(*) AS instability_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN vital_sign_limits vsl ON ce.itemid = vsl.itemid
  WHERE 
    ce.charttime BETWEEN 
      (SELECT intime FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE stay_id = ce.stay_id) 
      AND TIMESTAMP_ADD((SELECT intime FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE stay_id = ce.stay_id), INTERVAL 3 DAY)
    AND 
    ( 
      (vsl.label = 'Temperature' AND valuenum > vsl.threshold) OR
      (vsl.label = 'SpO2' AND valuenum < vsl.threshold) OR
      (vsl.label = 'Respiratory Rate' AND valuenum > vsl.threshold)
    )
  GROUP BY ce.subject_id, ce.hadm_id, ce.stay_id
),

-- Prepare patient data
patient_data AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    CASE 
      WHEN tp.subject_id IS NOT NULL THEN 'Transplant'
      ELSE 'Non-Transplant'
    END AS transplant_status,
    COALESCE(isc.instability_count, 0) AS instability_count,
    CASE 
      WHEN icu.outtime IS NULL THEN 1
      ELSE 0
    END AS mortality
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  LEFT JOIN transplant_patients tp ON p.subject_id = tp.subject_id
  LEFT JOIN instability_scores isc ON icu.stay_id = isc.stay_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 57 AND 67
)

-- Final analysis
SELECT 
  transplant_status,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY instability_count) AS median_instability_count,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY instability_count) AS p25_instability_count,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY instability_count) AS p75_instability_count,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) AS median_icu_los,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los) AS p25_icu_los,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los) AS p75_icu_los,
  AVG(mortality) AS mortality_rate
FROM patient_data
GROUP BY transplant_status;