WITH 
-- Step 1: Compute age at admission (44-year-olds)
patients_age AS (
  SELECT 
    p.subject_id,
    p.gender,  -- Added gender from patients table
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
),

-- Step 2: Filter 44-year-old males with postoperative complications
cohort AS (
  SELECT 
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients_age pa
    ON a.subject_id = pa.subject_id
  WHERE 
    pa.age_at_admission = 44
    AND pa.gender = 'M'  -- Fixed: use pa.gender instead of a.gender
    -- Postoperative: at least one procedure
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p 
      WHERE a.hadm_id = p.hadm_id
    )
    -- Complications: ICD-10 codes starting with T8 (T80-T88)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        a.hadm_id = d.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'T8%'
    )
),

-- Step 3: Determine ICU status
icu_status AS (
  SELECT 
    c.hadm_id,
    MAX(CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS icu_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.hadm_id = i.hadm_id
  GROUP BY c.hadm_id
),

-- Step 4: Compute hospital LOS (days)
los_data AS (
  SELECT 
    c.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.hadm_id = a.hadm_id
),

-- Step 5: Charlson Comorbidity Index (CCI) calculation
charlson_weights AS (
  SELECT pattern, category, weight
  FROM UNNEST([
    STRUCT('I21%' AS pattern, 'myocardial_infarction' AS category, 1 AS weight),
    STRUCT('I22%' AS pattern, 'myocardial_infarction' AS category, 1 AS weight),
    STRUCT('I50%' AS pattern, 'congestive_heart_failure' AS category, 1 AS weight),
    STRUCT('I69%' AS pattern, 'cerebrovascular_disease' AS category, 1 AS weight),
    STRUCT('F03%' AS pattern, 'dementia' AS category, 1 AS weight),
    STRUCT('J40%' AS pattern, 'chronic_pulmonary_disease' AS category, 1 AS weight),
    STRUCT('M05%' AS pattern, 'rheumatic_disease' AS category, 1 AS weight),
    STRUCT('K25%' AS pattern, 'peptic_ulcer_disease' AS category, 1 AS weight),
    STRUCT('K76%' AS pattern, 'mild_liver_disease' AS category, 1 AS weight),
    STRUCT('K74%' AS pattern, 'moderate_liver_disease' AS category, 3 AS weight),
    STRUCT('K70%' AS pattern, 'moderate_liver_disease' AS category, 3 AS weight),
    STRUCT('E11%' AS pattern, 'diabetes_without_cc' AS category, 1 AS weight),
    STRUCT('E10%' AS pattern, 'diabetes_without_cc' AS category, 1 AS weight),
    STRUCT('E13%' AS pattern, 'diabetes_without_cc' AS category, 1 AS weight),
    STRUCT('E14%' AS pattern, 'diabetes_without_cc' AS category, 1 AS weight),
    STRUCT('E08%' AS pattern, 'diabetes_with_cc' AS category, 2 AS weight),
    STRUCT('E09%' AS pattern, 'diabetes_with_cc' AS category, 2 AS weight),
    STRUCT('E102%' AS pattern, 'diabetes_with_cc' AS category, 2 AS weight),  -- Fixed: removed decimal for ICD-10 matching
    STRUCT('E112%' AS pattern, 'diabetes_with_cc' AS category, 2 AS weight),  -- Fixed: removed decimal for ICD-10 matching
    STRUCT('E122%' AS pattern, 'diabetes_with_cc' AS category, 2 AS weight),  -- Fixed: removed decimal for ICD-10 matching
    STRUCT('E132%' AS pattern, 'diabetes_with_cc' AS category, 2 AS weight),  -- Fixed: removed decimal for ICD-10 matching
    STRUCT('E142%' AS pattern, 'diabetes_with_cc' AS category, 2 AS weight),  -- Fixed: removed decimal for ICD-10 matching
    STRUCT('G81%' AS pattern, 'hemiplegia' AS category, 2 AS weight),
    STRUCT('I12%' AS pattern, 'renal_disease' AS category, 2 AS weight),
    STRUCT('I13%' AS pattern, 'renal_disease' AS category, 2 AS weight),
    STRUCT('N18%' AS pattern, 'renal_disease' AS category, 2 AS weight),
    STRUCT('C%' AS pattern, 'malignancy' AS category, 2 AS weight),
    STRUCT('C81%' AS pattern, 'lymphoma' AS category, 2 AS weight),
    STRUCT('C90%' AS pattern, 'leukemia' AS category, 2 AS weight),
    STRUCT('C77%' AS pattern, 'metastatic_solid_tumor' AS category, 6 AS weight),
    STRUCT('B20%' AS pattern, 'aids' AS category, 6 AS weight)
  ])
),
charlson_diagnoses AS (
  SELECT 
    d.hadm_id,
    cw.category,
    cw.weight
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN charlson_weights cw
    ON d.icd_code LIKE cw.pattern
  WHERE 
    d.hadm_id IN (SELECT hadm_id FROM cohort)
    AND d.icd_version = 10
),
charlson_scores AS (
  SELECT 
    hadm_id,
    COALESCE(SUM(weight), 0) AS charlson_score
  FROM (
    SELECT DISTINCT hadm_id, category, weight
    FROM charlson_diagnoses
  )
  GROUP BY hadm_id
),

-- Step 6: Mechanical ventilation flag (ICU-only)
mech_vent AS (
  SELECT DISTINCT 
    i.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON i.stay_id = p.stay_id
  WHERE 
    p.itemid IN (
      SELECT itemid 
      FROM `physionet-data.mimiciv_3_1_icu.d_items` 
      WHERE label LIKE '%ventilat%' AND category = 'Respiratory Care'
    )
),

-- Step 7: Vasopressors flag (ICU + non-ICU)
vasopressors AS (
  SELECT DISTINCT hadm_id
  FROM (
    -- ICU: inputevents
    SELECT i.hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.inputevents` i
    WHERE i.itemid IN (
      SELECT itemid 
      FROM `physionet-data.mimiciv_3_1_icu.d_items` 
      WHERE label LIKE '%norepinephrine%' 
        OR label LIKE '%dopamine%' 
        OR label LIKE '%epinephrine%' 
        OR label LIKE '%phenylephrine%' 
        OR label LIKE '%vasopressin%'
    )
    UNION DISTINCT
    -- Non-ICU: prescriptions
    SELECT p.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    WHERE 
      p.drug LIKE '%norepinephrine%' 
      OR p.drug LIKE '%dopamine%' 
      OR p.drug LIKE '%epinephrine%' 
      OR p.drug LIKE '%phenylephrine%' 
      OR p.drug LIKE '%vasopressin%'
  )
  WHERE hadm_id IN (SELECT hadm_id FROM cohort)
),

-- Step 8: RRT flag
rrt AS (
  SELECT DISTINCT hadm_id
  FROM (
    -- ICD-10-PCS codes for dialysis
    SELECT p.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    WHERE p.icd_code IN ('5A1D00Z', '5A1D60Z', '5A1D70Z', '5A1D80Z', '5A1D90Z')
    UNION DISTINCT
    -- ICU procedure events
    SELECT i.hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` i
    WHERE i.itemid IN (
      SELECT itemid 
      FROM `physionet-data.mimiciv_3_1_icu.d_items` 
      WHERE label LIKE '%dialysis%'
    )
  )
  WHERE hadm_id IN (SELECT hadm_id FROM cohort)
),

-- Step 9: Combine all patient data
patient_data AS (
  SELECT 
    c.hadm_id,
    icu.icu_flag,
    los.los_days,
    COALESCE(cs.charlson_score, 0) AS charlson_score,
    a.hospital_expire_flag,
    CASE WHEN mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS mech_vent_flag,
    CASE WHEN v.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS vasopressors_flag,
    CASE WHEN r.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS rrt_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.hadm_id = a.hadm_id
  LEFT JOIN icu_status icu
    ON c.hadm_id = icu.hadm_id
  LEFT JOIN los_data los
    ON c.hadm_id = los.hadm_id
  LEFT JOIN charlson_scores cs
    ON c.hadm_id = cs.hadm_id
  LEFT JOIN mech_vent mv
    ON c.hadm_id = mv.hadm_id
  LEFT JOIN vasopressors v
    ON c.hadm_id = v.hadm_id
  LEFT JOIN rrt r
    ON c.hadm_id = r.hadm_id
),

-- Step 10: Group by strata and compute metrics
grouped_data AS (
  SELECT 
    icu_flag,
    CASE 
      WHEN los_days <= 3 THEN '<=3'
      WHEN los_days BETWEEN 4 AND 6 THEN '4-6'
      WHEN los_days BETWEEN 7 AND 10 THEN '7-10'
      ELSE '>10'
    END AS los_group,
    CASE 
      WHEN charlson_score <= 3 THEN '<=3'
      WHEN charlson_score BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_group,
    COUNT(*) AS n,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(mech_vent_flag) AS mech_vent_pct,
    AVG(vasopressors_flag) AS vasopressors_pct,
    AVG(rrt_flag) AS rrt_pct
  FROM patient_data
  GROUP BY icu_flag, los_group, charlson_group
)

-- Step 11: Compute differences vs. ≤3-day LOS group
SELECT 
  CASE icu_flag WHEN 1 THEN 'ICU' ELSE 'non-ICU' END AS icu_status,
  los_group,
  charlson_group,
  n,
  ROUND(mortality_rate * 100, 2) AS mortality_pct,
  ROUND(mech_vent_pct * 100, 2) AS mech_vent_pct,
  ROUND(vasopressors_pct * 100, 2) AS vasopressors_pct,
  ROUND(rrt_pct * 100, 2) AS rrt_pct,
  ROUND((mortality_rate - base_mortality_rate) * 100, 2) AS absolute_difference_pct,
  ROUND(
    CASE 
      WHEN base_mortality_rate = 0 THEN NULL 
      ELSE (mortality_rate - base_mortality_rate) / base_mortality_rate * 100 
    END, 
    2
  ) AS relative_difference_pct
FROM (
  SELECT 
    *,
    MAX(CASE WHEN los_group = '<=3' THEN mortality_rate END) 
      OVER (PARTITION BY icu_flag, charlson_group) AS base_mortality_rate
  FROM grouped_data
)
ORDER BY icu_flag, charlson_group, 
  CASE los_group 
    WHEN '<=3' THEN 1 
    WHEN '4-6' THEN 2 
    WHEN '7-10' THEN 3 
    ELSE 4 
  END;