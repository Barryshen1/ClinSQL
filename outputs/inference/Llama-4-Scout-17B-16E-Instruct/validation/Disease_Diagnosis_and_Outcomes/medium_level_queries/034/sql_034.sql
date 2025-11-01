WITH 
-- Identify heart failure ICD codes (both ICD-9 and ICD-10)
heart_failure_icd AS (
  SELECT 
    icd_code, 
    icd_version,
    hadm_id,
    subject_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    icd_code IN (
      '428', '428.0', '428.1', '428.2', '428.3', '428.4', '428.9', 
      'I50', 'I50.0', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.5', 'I50.6', 'I50.7', 'I50.8', 'I50.9'
    )
),

-- Select relevant patient admissions
patients_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMPDIFF(DAY, a.admittime, COALESCE(a.dischtime, a.deathtime)) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    heart_failure_icd hfi 
      ON a.hadm_id = hfi.hadm_id AND a.subject_id = hfi.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
)

SELECT 
  CASE 
    WHEN los < 8 THEN 'LOS < 8'
    ELSE 'LOS ≥ 8'
  END AS los_category,
  COUNT(DISTINCT hadm_id) AS admission_count,
  SUM(hospital_expire_flag) AS mortality_count,
  SUM(hospital_expire_flag) / COUNT(DISTINCT hadm_id) AS mortality_rate
FROM 
  patients_admissions
GROUP BY 
  1

UNION ALL

SELECT 
  'Median Time-to-Death' AS los_category,
  NULL AS admission_count,
  NULL AS mortality_count,
  APPROX_QUANTILES(
    COALESCE(TIMESTAMPDIFF(DAY, admittime, deathtime), TIMESTAMPDIFF(DAY, admittime, dischtime)), 
    0.5
  )[OFFSET(0)] AS median_time_to_death
FROM 
  patients_admissions
WHERE 
  hospital_expire_flag = 1;