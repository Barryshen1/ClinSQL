WITH 
-- Define vital signs and their normal ranges
vital_signs AS (
  SELECT 
    ce.itemid,
    d.label,
    ce.valuenum,
    ce.charttime,
    ic.stay_id,
    ic.subject_id,
    ic.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` d ON ce.itemid = d.itemid
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic ON ce.hadm_id = ic.hadm_id AND ce.stay_id = ic.stay_id
  WHERE 
    d.category IN ('Vital Signs') 
    AND ce.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 1 DAY)
),

-- Calculate instability score (for simplicity, let's assume it's the number of abnormal vital signs)
instability_score AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    COUNT(*) AS instability_score
  FROM 
    vital_signs
  WHERE 
    -- Example criteria for abnormal vital signs
    (label = 'Heart Rate' AND (valuenum < 60 OR valuenum > 100))
    OR (label = 'Systolic Blood Pressure' AND (valuenum < 90 OR valuenum > 140))
    OR (label = 'Respiratory Rate' AND (valuenum < 10 OR valuenum > 30))
    OR (label = 'Temperature' AND (valuenum < 36 OR valuenum > 38))
    OR (label = 'Oxygen Saturation' AND valuenum < 90)
  GROUP BY 
    subject_id, hadm_id, stay_id
),

-- Filter for male patients aged 55-65 post-cardiac arrest
target_patients AS (
  SELECT 
    a.hadm_id,
    p.subject_id,
    ic.stay_id,
    a.admission_type
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic ON a.hadm_id = ic.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
    AND a.admission_type = 'cardiac arrest'
),

-- Combine instability scores with target patients
patient_scores AS (
  SELECT 
    tp.hadm_id,
    tp.subject_id,
    tp.stay_id,
    COALESCE(instability.instability_score, 0) AS instability_score,
    ic.los AS icu_los,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 1 
      ELSE 0 
    END AS mortality
  FROM 
    target_patients tp
  LEFT JOIN 
    instability_score instability ON tp.hadm_id = instability.hadm_id AND tp.stay_id = instability.stay_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic ON tp.hadm_id = ic.hadm_id AND tp.stay_id = ic.stay_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON tp.hadm_id = a.hadm_id
),

-- Calculate percentile and statistics
percentiles AS (
  SELECT 
    PERCENTILE_CONT(0.7) WITHIN GROUP (ORDER BY instability_score) AS percentile_70,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY instability_score) AS percentile_90
  FROM 
    patient_scores
)

SELECT 
  p.percentile_70,
  AVG(CASE WHEN ps.instability_score >= p.percentile_90 THEN ps.icu_los END) AS mean_icu_los_most_unstable,
  AVG(CASE WHEN ps.instability_score >= p.percentile_90 THEN ps.mortality END) AS mortality_most_unstable
FROM 
  patient_scores ps
CROSS JOIN 
  percentiles p;