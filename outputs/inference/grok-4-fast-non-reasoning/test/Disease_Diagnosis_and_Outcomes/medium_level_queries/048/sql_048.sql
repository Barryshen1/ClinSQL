WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.hadm_id IS NOT NULL
),
comorbidities AS (
  SELECT 
    pa.*,
    CASE WHEN di.icd_code LIKE 'N18%' AND di.icd_version = '10' THEN 1 ELSE 0 END AS has_ckd,
    CASE 
      WHEN di.icd_code LIKE 'E10%' AND di.icd_version = '10' THEN 1
      WHEN di.icd_code LIKE 'E11%' AND di.icd_version = '10' THEN 1
      WHEN di.icd_code LIKE 'E13%' AND di.icd_version = '10' THEN 1
      ELSE 0 
    END AS has_diabetes
  FROM 
    patient_admissions pa
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON 
    pa.hadm_id = di.hadm_id
),
stratified_data AS (
  SELECT 
    hadm_id,
    hospital_expire_flag,
    MAX(has_ckd) AS has_ckd,
    MAX(has_diabetes) AS has_diabetes,
    CASE 
      WHEN los_days < 8 THEN 'LOS < 8 days'
      ELSE 'LOS >= 8 days'
    END AS los_group
  FROM 
    comorbidities
  GROUP BY 
    hadm_id, hospital_expire_flag, los_days, los_group
)
SELECT 
  los_group,
  COUNT(DISTINCT hadm_id) AS num_admissions,
  ROUND((SUM(hospital_expire_flag) * 100.0 / COUNT(DISTINCT hadm_id)), 2) AS mortality_pct,
  ROUND((SUM(has_ckd) * 100.0 / COUNT(DISTINCT hadm_id)), 2) AS ckd_prevalence_pct,
  ROUND((SUM(has_diabetes) * 100.0 / COUNT(DISTINCT hadm_id)), 2) AS diabetes_prevalence_pct
FROM 
  stratified_data
GROUP BY 
  los_group
ORDER BY 
  CASE 
    WHEN los_group = 'LOS < 8 days' THEN 1 
    ELSE 2 
  END;