WITH patient_diagnoses AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender,
    -- Check for type 2 diabetes (ICD-10: E11)
    MAX(CASE WHEN di.icd_version = 10 AND di.icd_code LIKE 'E11%' THEN 1 ELSE 0 END) AS has_t2dm,
    -- Check for heart failure (ICD-10: I50%)
    MAX(CASE WHEN di.icd_version = 10 AND di.icd_code LIKE 'I50%' THEN 1 ELSE 0 END) AS has_hf
  FROM
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN
    `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age >= 79 AND p.anchor_age <= 89
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, p.anchor_age, p.gender
),
qualifying_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM
    patient_diagnoses
  WHERE
    has_t2dm = 1 AND has_hf = 1
),
first_admission AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime
  FROM
    qualifying_admissions
  WHERE
    rn = 1
),
glp1_prescriptions AS (
  SELECT DISTINCT
    fa.subject_id,
    fa.hadm_id,
    fa.admittime,
    fa.dischtime,
    -- Flag if GLP-1 agonist was prescribed in first 12 hours
    MAX(CASE WHEN p.starttime >= fa.admittime AND p.starttime <= DATETIME_ADD(fa.admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END) AS glp1_early,
    -- Flag if GLP-1 agonist was prescribed in last 24 hours
    MAX(CASE WHEN p.starttime >= DATETIME_SUB(fa.dischtime, INTERVAL 24 HOUR) AND p.starttime <= fa.dischtime THEN 1 ELSE 0 END) AS glp1_late
  FROM
    first_admission fa
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp`.prescriptions p
    ON fa.hadm_id = p.hadm_id
    AND LOWER(p.drug) IN (
      'liraglutide', 'semaglutide', 'dulaglutide', 'exenatide', 
      'lixisenatide', 'tirzepatide', 'dulaglutide pen', 'semaglutide pen',
      'liraglutide injection', 'exenatide extended release'
    )
  GROUP BY
    fa.subject_id, fa.hadm_id, fa.admittime, fa.dischtime
),
summary AS (
  SELECT
    COUNT(*) AS total_patients,
    SUM(glp1_early) AS early_count,
    SUM(glp1_late) AS late_count
  FROM
    glp1_prescriptions
)
SELECT
  total_patients,
  early_count,
  late_count,
  ROUND((early_count / total_patients) * 100, 2) AS percent_early,
  ROUND((late_count / total_patients) * 100, 2) AS percent_late,
  ROUND((late_count / total_patients) * 100 - (early_count / total_patients) * 100, 2) AS net_percentage_point_change
FROM
  summary;