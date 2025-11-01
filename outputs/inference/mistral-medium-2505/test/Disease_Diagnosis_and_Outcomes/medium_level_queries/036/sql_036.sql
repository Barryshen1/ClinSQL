WITH
-- Define heart failure ICD codes (ICD-9 and ICD-10)
heart_failure_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%heart failure%'
     OR icd_code IN ('428', 'I50', 'I50.1', 'I50.9', '428.0', '428.1', '428.2', '428.3', '428.4')
),

-- Define CKD ICD codes
ckd_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%chronic kidney disease%'
     OR LOWER(long_title) LIKE '%renal failure%'
     OR icd_code IN ('585', 'N18', 'N18.1', 'N18.2', 'N18.3', 'N18.4', 'N18.5', 'N18.6', 'N18.9')
),

-- Define diabetes ICD codes
diabetes_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%diabetes%'
     OR icd_code IN ('250', 'E11', 'E13', 'E10', 'E14')
),

-- Get female patients aged 39-49 with heart failure
female_hf_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON p.subject_id = d.subject_id
  JOIN heart_failure_codes hf ON d.icd_code = hf.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
),

-- Get first admission for each patient
first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Calculate number of distinct ICD codes as comorbidity proxy
    (SELECT COUNT(DISTINCT icd_code)
     FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
     WHERE d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN female_hf_patients f ON a.subject_id = f.subject_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) = 1
),

-- Calculate comorbidity tertiles
comorbidity_tertiles AS (
  SELECT
    hadm_id,
    los_days,
    hospital_expire_flag,
    comorbidity_count,
    NTILE(3) OVER (ORDER BY comorbidity_count) AS comorbidity_tertile
  FROM first_admissions
),

-- Get CKD and diabetes status for each admission
comorbidities AS (
  SELECT
    c.hadm_id,
    MAX(CASE WHEN ckd.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN diab.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS has_diabetes
  FROM comorbidity_tertiles c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON c.hadm_id = d.hadm_id
  LEFT JOIN ckd_codes ckd ON d.icd_code = ckd.icd_code
  LEFT JOIN diabetes_codes diab ON d.icd_code = diab.icd_code
  GROUP BY c.hadm_id
),

-- Final dataset with all needed information
final_dataset AS (
  SELECT
    c.hadm_id,
    c.los_days,
    c.hospital_expire_flag,
    c.comorbidity_tertile,
    co.has_ckd,
    co.has_diabetes,
    CASE WHEN c.los_days <= 5 THEN '≤5 days' ELSE '>5 days' END AS los_group,
    CASE
      WHEN c.comorbidity_tertile = 1 THEN 'Low'
      WHEN c.comorbidity_tertile = 2 THEN 'Medium'
      WHEN c.comorbidity_tertile = 3 THEN 'High'
    END AS comorbidity_group
  FROM comorbidity_tertiles c
  JOIN comorbidities co ON c.hadm_id = co.hadm_id
)

-- Final aggregation
SELECT
  los_group,
  comorbidity_group,
  COUNT(*) AS N,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 1) AS mortality_percentage,
  ROUND(100 * SUM(has_ckd) / COUNT(*), 1) AS ckd_prevalence_percentage,
  ROUND(100 * SUM(has_diabetes) / COUNT(*), 1) AS diabetes_prevalence_percentage
FROM final_dataset
GROUP BY los_group, comorbidity_group
ORDER BY los_group, comorbidity_group;