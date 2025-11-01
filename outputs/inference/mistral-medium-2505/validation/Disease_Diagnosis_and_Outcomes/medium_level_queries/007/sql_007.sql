WITH
-- Define heart failure ICD codes
heart_failure_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'I50.%'
),

-- Get female patients aged 51-61 with heart failure
base_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    COUNT(DISTINCT d.icd_code) AS num_diagnoses
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN heart_failure_codes hf ON d.icd_code = hf.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
  GROUP BY
    p.subject_id, p.gender, p.anchor_age,
    a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
),

-- Identify ICU stays
icu_stays AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

-- Categorize comorbidity burden
comorbidity_categories AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN num_diagnoses BETWEEN 0 AND 2 THEN 'Low'
      WHEN num_diagnoses BETWEEN 3 AND 5 THEN 'Medium'
      ELSE 'High'
    END AS comorbidity_burden
  FROM base_patients
),

-- Identify mechanical ventilation, vasopressors, and RRT
icu_treatments AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    MAX(CASE WHEN ce.itemid IN (223848, 223849) THEN 1 ELSE 0 END) AS has_mv, -- Mechanical ventilation
    MAX(CASE WHEN ce.itemid IN (221906, 222315, 221289) THEN 1 ELSE 0 END) AS has_vaso, -- Vasopressors
    MAX(CASE WHEN ce.itemid IN (225161, 225162) THEN 1 ELSE 0 END) AS has_rrt -- RRT
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON i.subject_id = ce.subject_id AND i.hadm_id = ce.hadm_id
  GROUP BY i.subject_id, i.hadm_id
),

-- Combine all data
final_dataset AS (
  SELECT
    bp.subject_id,
    bp.hadm_id,
    bp.gender,
    bp.anchor_age,
    bp.los_days,
    bp.hospital_expire_flag,
    CASE WHEN icu.subject_id IS NOT NULL THEN 'ICU' ELSE 'No ICU' END AS icu_status,
    CASE WHEN bp.los_days < 8 THEN '<8 days' ELSE '>=8 days' END AS los_category,
    cc.comorbidity_burden,
    it.has_mv,
    it.has_vaso,
    it.has_rrt
  FROM base_patients bp
  LEFT JOIN icu_stays icu ON bp.subject_id = icu.subject_id AND bp.hadm_id = icu.hadm_id
  LEFT JOIN comorbidity_categories cc ON bp.subject_id = cc.subject_id AND bp.hadm_id = cc.hadm_id
  LEFT JOIN icu_treatments it ON bp.subject_id = it.subject_id AND bp.hadm_id = it.hadm_id
)

-- Final analysis
SELECT
  icu_status,
  los_category,
  comorbidity_burden,
  COUNT(*) AS patient_count,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate,
  ROUND(SUM(has_mv) * 100.0 / NULLIF(COUNT(*), 0), 2) AS mv_prevalence,
  ROUND(SUM(has_vaso) * 100.0 / NULLIF(COUNT(*), 0), 2) AS vaso_prevalence,
  ROUND(SUM(has_rrt) * 100.0 / NULLIF(COUNT(*), 0), 2) AS rrt_prevalence
FROM final_dataset
GROUP BY icu_status, los_category, comorbidity_burden
ORDER BY icu_status, los_category, comorbidity_burden;