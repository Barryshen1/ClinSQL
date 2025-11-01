WITH
-- Define heart failure ICD codes (example codes, should be expanded)
heart_failure_icd AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN (
    '4280', '4281', '42820', '42821', '42822', '42823', '42830', '42831', '42832', '42833',
    '42840', '42841', '42842', '42843', '4289', 'I501', 'I5020', 'I5021', 'I5022', 'I5023',
    'I5030', 'I5031', 'I5032', 'I5033', 'I5040', 'I5041', 'I5042', 'I5043', 'I509'
  )
),

-- Get patients with heart failure
hf_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN heart_failure_icd hf ON d.icd_code = hf.icd_code
),

-- Calculate Charlson Comorbidity Index (simplified example)
charlson_scores AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(CASE
      WHEN icd_code IN ('4100', '4101', '4102', '4103', '4104', '4105', '4106', '4107', '4108', '4109') THEN 1 -- Myocardial infarction
      WHEN icd_code IN ('4280', '4281', '42820', '42821', '42822', '42823', '42830', '42831', '42832', '42833',
                        '42840', '42841', '42842', '42843', '4289', 'I501', 'I5020', 'I5021', 'I5022', 'I5023',
                        'I5030', 'I5031', 'I5032', 'I5033', 'I5040', 'I5041', 'I5042', 'I5043', 'I509') THEN 1 -- Congestive heart failure
      -- Add more conditions with appropriate weights
      ELSE 0
    END) AS charlson_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY subject_id, hadm_id
),

-- Get ICU interventions
icu_interventions AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN c.itemid IN (223848, 223849) THEN 1 ELSE 0 END) AS mech_vent, -- Mechanical ventilation
    MAX(CASE WHEN c.itemid IN (221906, 221907, 221908, 221909, 221910) THEN 1 ELSE 0 END) AS vasopressor, -- Vasopressors
    MAX(CASE WHEN c.itemid IN (225161, 225162, 225163) THEN 1 ELSE 0 END) AS rrt -- Renal replacement therapy
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  GROUP BY c.subject_id, c.hadm_id
),

-- Main patient cohort with all required data
cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS has_icu,
    cs.charlson_score,
    COALESCE(ii.mech_vent, 0) AS mech_vent,
    COALESCE(ii.vasopressor, 0) AS vasopressor,
    COALESCE(ii.rrt, 0) AS rrt
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN hf_patients hf ON p.subject_id = hf.subject_id AND a.hadm_id = hf.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  LEFT JOIN charlson_scores cs ON p.subject_id = cs.subject_id AND a.hadm_id = cs.hadm_id
  LEFT JOIN icu_interventions ii ON p.subject_id = ii.subject_id AND a.hadm_id = ii.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 44 AND 54
)

-- Final analysis
SELECT
  CASE WHEN has_icu = 1 THEN 'ICU' ELSE 'No ICU' END AS icu_status,
  CASE WHEN los_days <= 7 THEN '≤7 days' ELSE '>7 days' END AS los_category,
  CASE
    WHEN charlson_score BETWEEN 0 AND 1 THEN '0-1'
    WHEN charlson_score = 2 THEN '2'
    WHEN charlson_score >= 3 THEN '≥3'
    ELSE 'Unknown'
  END AS charlson_category,
  COUNT(*) AS patient_count,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 1) AS mortality_rate,
  -- Calculate 95% CI for mortality rate
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*) - 1.96 * SQRT((SUM(hospital_expire_flag) / COUNT(*) * (1 - SUM(hospital_expire_flag) / COUNT(*) / NULLIF(COUNT(*), 0)))), 1) AS ci_lower,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*) + 1.96 * SQRT((SUM(hospital_expire_flag) / COUNT(*) * (1 - SUM(hospital_expire_flag) / COUNT(*) / NULLIF(COUNT(*), 0)))), 1) AS ci_upper,
  ROUND(100 * SUM(mech_vent) / COUNT(*), 1) AS mech_vent_rate,
  ROUND(100 * SUM(vasopressor) / COUNT(*), 1) AS vasopressor_rate,
  ROUND(100 * SUM(rrt) / COUNT(*), 1) AS rrt_rate
FROM cohort
GROUP BY icu_status, los_category, charlson_category
ORDER BY icu_status, los_category, charlson_category;