WITH patients_filtered AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit,
    -- Compute LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 52 AND 62
),

-- Get all diagnoses for these admissions
diagnoses AS (
  SELECT 
    di.hadm_id,
    di.icd_code,
    di.icd_version,
    d.long_title
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
),

-- Classify stroke type per admission
stroke_classification AS (
  SELECT 
    hadm_id,
    MAX(CASE 
      WHEN (icd_version = 9 AND icd_code IN ('434', '433')) OR 
           (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I63', 'I65', 'I66'))
      THEN 'ischemic'
      WHEN (icd_version = 9 AND icd_code IN ('430', '431', '432')) OR 
           (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I60', 'I61', 'I62'))
      THEN 'hemorrhagic'
      ELSE NULL 
    END) AS stroke_type
  FROM diagnoses
  GROUP BY hadm_id
  HAVING MAX(CASE 
      WHEN (icd_version = 9 AND icd_code IN ('434', '433')) OR 
           (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I63', 'I65', 'I66'))
      THEN 'ischemic'
      WHEN (icd_version = 9 AND icd_code IN ('430', '431', '432')) OR 
           (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I60', 'I61', 'I62'))
      THEN 'hemorrhagic'
      ELSE NULL 
    END) IS NOT NULL
),

-- Identify comorbidities: CKD and Diabetes
comorbidities AS (
  SELECT 
    d.hadm_id,
    MAX(CASE 
      WHEN (d.icd_version = 9 AND d.icd_code IN ('585', 'V56')) OR 
           (d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) = 'N18')
      THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE 
      WHEN (d.icd_version = 9 AND d.icd_code IN ('250')) OR 
           (d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) = 'E11')
      THEN 1 ELSE 0 END) AS has_diabetes
  FROM diagnoses d
  GROUP BY d.hadm_id
),

-- Combine all data
cohort AS (
  SELECT 
    pf.subject_id,
    pf.hadm_id,
    sc.stroke_type,
    pf.hospital_expire_flag,
    pf.los_days,
    COALESCE(com.has_ckd, 0) AS has_ckd,
    COALESCE(com.has_diabetes, 0) AS has_diabetes
  FROM patients_filtered pf
  INNER JOIN stroke_classification sc
    ON pf.hadm_id = sc.hadm_id
  LEFT JOIN comorbidities com
    ON pf.hadm_id = com.hadm_id
)

-- Final aggregation by stroke type
SELECT
  stroke_type,
  -- In-hospital mortality (%)
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_pct,
  -- Median LOS >= 8 days (%)
  ROUND(100.0 * SUM(CASE WHEN los_days >= 8 THEN 1 ELSE 0 END) / COUNT(*), 2) AS los_ge8_pct,
  -- CKD prevalence (%)
  ROUND(100.0 * SUM(has_ckd) / COUNT(*), 2) AS ckd_prevalence_pct,
  -- Diabetes prevalence (%)
  ROUND(100.0 * SUM(has_diabetes) / COUNT(*), 2) AS diabetes_prevalence_pct
FROM cohort
GROUP BY stroke_type
ORDER BY stroke_type;