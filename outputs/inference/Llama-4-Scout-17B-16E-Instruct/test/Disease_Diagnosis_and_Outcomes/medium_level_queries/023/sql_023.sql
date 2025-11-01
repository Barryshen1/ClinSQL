WITH 
  -- Identify female patients aged 52-62
  eligible_patients AS (
    SELECT subject_id, anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 52 AND 62
  ),
  
  -- Identify stroke type (ischemic vs hemorrhagic)
  stroke_patients AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      CASE 
        WHEN di.icd_code IN ('433', '433.0', '433.1', '433.2', '433.3', '433.4', '433.5', '433.6', '433.7', '433.8', '433.9') THEN 'ischemic'
        WHEN di.icd_code IN ('430', '431', '432', '432.0', '432.1', '432.2', '432.3', '432.4', '432.5', '432.6', '432.7', '432.8', '432.9') THEN 'hemorrhagic'
        ELSE 'other'
      END AS stroke_type
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      eligible_patients ep ON a.subject_id = ep.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
    WHERE 
      di.icd_code IN (
        '433', '433.0', '433.1', '433.2', '433.3', '433.4', '433.5', '433.6', '433.7', '433.8', '433.9',
        '430', '431', '432', '432.0', '432.1', '432.2', '432.3', '432.4', '432.5', '432.6', '432.7', '432.8', '432.9'
      )
  ),
  
  -- Calculate in-hospital mortality, LOS, and comorbidities
  patient_outcomes AS (
    SELECT 
      sp.subject_id, 
      sp.hadm_id, 
      sp.stroke_type,
      a.hospital_expire_flag,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
      CASE 
        WHEN di.icd_code IN ('585', '585.1', '585.2', '585.3', '585.4', '585.5', '585.6', '585.7', '585.8', '585.9') THEN 'CKD'
        WHEN di.icd_code IN ('250', '250.0', '250.1', '250.2', '250.3', '250.4', '250.5', '250.6', '250.7', '250.8', '250.9') THEN 'diabetes'
        ELSE NULL
      END AS comorbidity
    FROM 
      stroke_patients sp
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a ON sp.hadm_id = a.hadm_id
    LEFT JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  ),
  
  -- Aggregate patient level outcomes
  patient_level_outcomes AS (
    SELECT 
      subject_id,
      hadm_id,
      stroke_type,
      hospital_expire_flag,
      los,
      ARRAY_AGG(DISTINCT comorbidity IGNORE NULLS) AS comorbidities
    FROM 
      patient_outcomes
    GROUP BY 
      subject_id,
      hadm_id,
      stroke_type,
      hospital_expire_flag,
      los
  )

SELECT 
  stroke_type,
  COUNT(CASE WHEN hospital_expire_flag = 1 THEN hadm_id END) / COUNT(hadm_id) AS mortality_rate,
  APPROX_QUANTILES(los, 1000)[OFFSET(500)] AS median_los,
  CASE 
    WHEN los < 8 THEN '<8 days'
    ELSE '≥8 days'
  END AS los_category,
  COUNT(CASE WHEN 'CKD' IN comorbidities THEN hadm_id END) / COUNT(hadm_id) AS ckd_prevalence,
  COUNT(CASE WHEN 'diabetes' IN comorbidities THEN hadm_id END) / COUNT(hadm_id) AS diabetes_prevalence
FROM 
  patient_level_outcomes
GROUP BY 
  stroke_type,
  los_category
ORDER BY 
  stroke_type,
  los_category;