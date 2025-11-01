WITH 
-- Define heart failure ICD codes
heart_failure_icd AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE long_title LIKE '%Heart failure%'
),

-- Calculate Charlson comorbidity index (simplified for this example)
charlson_index AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    -- Simplified Charlson score calculation for illustration
    CASE 
      WHEN d.icd_code IN ('398.0', '402.0', '402.1', '402.9', '404.0', '404.1', '404.9', '428.0') THEN 1
      ELSE 0
    END AS charlson_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
),

-- Identify ICU stays
icu_stays AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    los
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

-- Identify interventions
interventions AS (
  SELECT 
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    CASE 
      WHEN ce.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label LIKE '%Ventilation%') THEN 'Mechanical Ventilation'
      WHEN ce.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label LIKE '%Vasopressor%') THEN 'Vasopressor'
      WHEN ce.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label LIKE '%Renal Replacement Therapy%') THEN 'RRT'
      ELSE NULL
    END AS intervention
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE ce.value = 'Yes'
),

-- Main patient data
patients_data AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    CASE 
      WHEN ic.stay_id IS NOT NULL THEN 'ICU'
      ELSE 'No ICU'
    END AS icu_status,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    COALESCE(ci.charlson_score, 0) AS charlson_score
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  LEFT JOIN icu_stays ic ON a.hadm_id = ic.hadm_id
  LEFT JOIN charlson_index ci ON a.hadm_id = ci.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code IN (SELECT icd_code FROM heart_failure_icd)
    )
)

-- Final analysis
SELECT 
  pd.icu_status,
  CASE 
    WHEN pd.los <= 7 THEN 'LOS ≤7'
    ELSE 'LOS >7'
  END AS los_category,
  CASE 
    WHEN pd.charlson_score BETWEEN 0 AND 1 THEN 'Charlson 0-1'
    WHEN pd.charlson_score = 2 THEN 'Charlson 2'
    ELSE 'Charlson ≥3'
  END AS charlson_category,
  AVG(pd.hospital_expire_flag) * 100 AS mortality_rate,
  -- Calculate 95% CI
  APPROX_QUANTILES(pd.hospital_expire_flag, 0.025)[1] * 100 AS ci_025,
  APPROX_QUANTILES(pd.hospital_expire_flag, 0.975)[1] * 100 AS ci_975,
  SUM(CASE WHEN i.intervention = 'Mechanical Ventilation' THEN 1 ELSE 0 END) * 100.0 / COUNT(pd.subject_id) AS mech_vent_rate,
  SUM(CASE WHEN i.intervention = 'Vasopressor' THEN 1 ELSE 0 END) * 100.0 / COUNT(pd.subject_id) AS vasopressor_rate,
  SUM(CASE WHEN i.intervention = 'RRT' THEN 1 ELSE 0 END) * 100.0 / COUNT(pd.subject_id) AS rrt_rate
FROM patients_data pd
LEFT JOIN interventions i ON pd.hadm_id = i.hadm_id
GROUP BY 
  pd.icu_status,
  los_category,
  charlson_category
ORDER BY 
  pd.icu_status,
  los_category,
  charlson_category;