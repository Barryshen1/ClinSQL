WITH
-- Get our target patient (44-year-old male)
target_patient AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age = 44
  LIMIT 1
),

-- Get all admissions for this patient
patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 3 THEN '≤3'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 6 THEN '4-6'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 7 AND 10 THEN '7-10'
      ELSE '>10'
    END AS los_category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN target_patient tp ON a.subject_id = tp.subject_id
),

-- Identify ICU stays
patient_icu_stays AS (
  SELECT
    hadm_id,
    intime,
    outtime,
    first_careunit
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE subject_id = (SELECT subject_id FROM target_patient)
),

-- Calculate Charlson score (simplified version)
charlson_scores AS (
  SELECT
    hadm_id,
    SUM(CASE
      WHEN icd_code IN ('I10', 'I11', 'I12', 'I13', 'I15') THEN 1 -- Myocardial infarction
      WHEN icd_code IN ('I60', 'I61', 'I62', 'I63', 'I64') THEN 1 -- Cerebrovascular disease
      WHEN icd_code IN ('E10', 'E11', 'E12', 'E13', 'E14') THEN 1 -- Diabetes
      -- Add more conditions as needed for full Charlson score
      ELSE 0
    END) AS charlson_score,
    CASE
      WHEN SUM(CASE
        WHEN icd_code IN ('I10', 'I11', 'I12', 'I13', 'I15') THEN 1
        WHEN icd_code IN ('I60', 'I61', 'I62', 'I63', 'I64') THEN 1
        WHEN icd_code IN ('E10', 'E11', 'E12', 'E13', 'E14') THEN 1
        ELSE 0
      END) <= 3 THEN '≤3'
      WHEN SUM(CASE
        WHEN icd_code IN ('I10', 'I11', 'I12', 'I13', 'I15') THEN 1
        WHEN icd_code IN ('I60', 'I61', 'I62', 'I63', 'I64') THEN 1
        WHEN icd_code IN ('E10', 'E11', 'E12', 'E13', 'E14') THEN 1
        ELSE 0
      END) BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_category
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE subject_id = (SELECT subject_id FROM target_patient)
  GROUP BY hadm_id
),

-- Identify mechanical ventilation
mechanical_ventilation AS (
  SELECT DISTINCT
    hadm_id,
    1 AS has_mechanical_ventilation
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE subject_id = (SELECT subject_id FROM target_patient)
  AND itemid IN (223848, 223849) -- Example itemids for mechanical ventilation
),

-- Identify vasopressors
vasopressors AS (
  SELECT DISTINCT
    hadm_id,
    1 AS has_vasopressors
  FROM `physionet-data.mimiciv_3_1_icu.inputevents`
  WHERE subject_id = (SELECT subject_id FROM target_patient)
  AND itemid IN (221906, 221907, 221908) -- Example itemids for vasopressors
),

-- Identify RRT
rrt AS (
  SELECT DISTINCT
    hadm_id,
    1 AS has_rrt
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE subject_id = (SELECT subject_id FROM target_patient)
  AND itemid IN (225161, 225162) -- Example itemids for RRT
),

-- Combine all data
combined_data AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.los_days,
    pa.los_category,
    cs.charlson_score,
    cs.charlson_category,
    pa.hospital_expire_flag,
    CASE WHEN pis.hadm_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
    mv.has_mechanical_ventilation,
    vp.has_vasopressors,
    r.has_rrt
  FROM patient_admissions pa
  LEFT JOIN patient_icu_stays pis ON pa.hadm_id = pis.hadm_id
  LEFT JOIN charlson_scores cs ON pa.hadm_id = cs.hadm_id
  LEFT JOIN mechanical_ventilation mv ON pa.hadm_id = mv.hadm_id
  LEFT JOIN vasopressors vp ON pa.hadm_id = vp.hadm_id
  LEFT JOIN rrt r ON pa.hadm_id = r.hadm_id
)

-- Final analysis
SELECT
  icu_status,
  los_category,
  charlson_category,
  COUNT(*) AS patient_count,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(SUM(hospital_expire_flag) / COUNT(*) * 100, 2) AS mortality_rate,
  ROUND(SUM(CASE WHEN los_category = '≤3' THEN hospital_expire_flag ELSE 0 END) / NULLIF(SUM(CASE WHEN los_category = '≤3' THEN 1 ELSE 0 END), 0) * 100, 2) AS reference_mortality,
  ROUND(SUM(hospital_expire_flag) / COUNT(*) * 100 - SUM(CASE WHEN los_category = '≤3' THEN hospital_expire_flag ELSE 0 END) / NULLIF(SUM(CASE WHEN los_category = '≤3' THEN 1 ELSE 0 END), 0) * 100, 2) AS absolute_difference,
  ROUND((SUM(hospital_expire_flag) / COUNT(*) * 100) / NULLIF(SUM(CASE WHEN los_category = '≤3' THEN hospital_expire_flag ELSE 0 END) / NULLIF(SUM(CASE WHEN los_category = '≤3' THEN 1 ELSE 0 END), 0) * 100, 0) - 1, 2) AS relative_difference,
  ROUND(SUM(has_mechanical_ventilation) / COUNT(*) * 100, 2) AS mechanical_ventilation_rate,
  ROUND(SUM(has_vasopressors) / COUNT(*) * 100, 2) AS vasopressors_rate,
  ROUND(SUM(has_rrt) / COUNT(*) * 100, 2) AS rrt_rate
FROM combined_data
GROUP BY icu_status, los_category, charlson_category
ORDER BY icu_status, los_category, charlson_category;