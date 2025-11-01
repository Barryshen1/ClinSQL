WITH patient_cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate age at admission using MIMIC-IV anchor methodology
    p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime)) AS age_at_admission,
    -- Calculate LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    -- Filter for age 43-53 at admission
    AND (p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime))) BETWEEN 43 AND 53
    -- Ensure valid admission dates
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- Identify patients with heart failure diagnosis
heart_failure_patients AS (
  SELECT DISTINCT
    cohort.subject_id,
    cohort.hadm_id,
    cohort.admittime,
    cohort.dischtime,
    cohort.hospital_expire_flag,
    cohort.age_at_admission,
    cohort.los_days
  FROM patient_cohort cohort
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON cohort.hadm_id = diag.hadm_id
  WHERE 
    -- ICD-9 codes for heart failure (428.*)
    (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
    OR
    -- ICD-10 codes for heart failure (I50.*)
    (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
),

-- Calculate comorbidity burden (count of non-HF diagnoses)
comorbidity_burden AS (
  SELECT
    hf.*,
    (SELECT COUNT(*) 
     FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
     WHERE d.hadm_id = hf.hadm_id
       AND NOT ((d.icd_version = 9 AND d.icd_code LIKE '428%') 
                OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%'))) AS comorbidity_count
  FROM heart_failure_patients hf
),

-- Calculate quartiles for LOS
los_quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY los_days) AS los_quartile
  FROM comorbidity_burden
),

-- Categorize comorbidity burden
burden_categories AS (
  SELECT
    *,
    CASE
      WHEN comorbidity_count = 0 THEN 'low'  -- Only HF diagnosis
      WHEN comorbidity_count BETWEEN 1 AND 2 THEN 'medium'
      ELSE 'high'
    END AS burden_category
  FROM los_quartiles
)

-- Final result: mortality rate by LOS quartile and burden category
SELECT
  los_quartile,
  burden_category,
  COUNT(*) AS patient_count,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_rate_pct
FROM burden_categories
GROUP BY los_quartile, burden_category
ORDER BY los_quartile, burden_category;