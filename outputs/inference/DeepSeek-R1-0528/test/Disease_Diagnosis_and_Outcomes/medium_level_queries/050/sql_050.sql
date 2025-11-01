WITH shock_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code = '78552') OR
    (icd_version = 10 AND icd_code IN ('R6521', 'T8112'))
),
sepsis_candidates AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND (icd_code LIKE '038%' OR icd_code IN ('99591', '99592'))) OR
    (icd_version = 10 AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%' OR icd_code = 'R6520'))
),
sepsis_admissions AS (
  SELECT s.hadm_id
  FROM sepsis_candidates s
  LEFT JOIN shock_admissions sh ON s.hadm_id = sh.hadm_id
  WHERE sh.hadm_id IS NULL
),
base_cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON adm.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND adm.hadm_id IN (SELECT hadm_id FROM sepsis_admissions)
    AND p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) BETWEEN 75 AND 85
),
comorbidities AS (
  SELECT 
    hadm_id,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code LIKE '585%') OR
               (icd_version = 10 AND icd_code LIKE 'N18%') THEN 1 
          ELSE 0 
        END) AS ckd,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code LIKE '250%') OR
               (icd_version = 10 AND icd_code LIKE 'E1[0-4]%') THEN 1 
          ELSE 0 
        END) AS diabetes,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code = '42731') OR
               (icd_version = 10 AND icd_code LIKE 'I48%') THEN 1 
          ELSE 0 
        END) AS afib,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code LIKE '40[1-5]%') OR
               (icd_version = 10 AND icd_code LIKE 'I1[0-5]%') THEN 1 
          ELSE 0 
        END) AS hypertension
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort_with_comorbidities AS (
  SELECT 
    b.*,
    COALESCE(c.ckd, 0) AS ckd,
    COALESCE(c.diabetes, 0) AS diabetes,
    COALESCE(c.afib, 0) AS afib,
    COALESCE(c.hypertension, 0) AS hypertension,
    CASE WHEN b.los_days <= 5 THEN '<=5' ELSE '>5' END AS los_group
  FROM base_cohort b
  LEFT JOIN comorbidities c ON b.hadm_id = c.hadm_id
)
SELECT 
  comorbidity,
  los_group,
  has_comorbidity,
  total_patients,
  deaths,
  ROUND(100.0 * deaths / total_patients, 2) AS mortality_percentage
FROM (
  SELECT 
    'CKD' AS comorbidity,
    los_group,
    ckd AS has_comorbidity,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS deaths
  FROM cohort_with_comorbidities
  GROUP BY los_group, ckd
  UNION ALL
  SELECT 
    'Diabetes' AS comorbidity,
    los_group,
    diabetes AS has_comorbidity,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS deaths
  FROM cohort_with_comorbidities
  GROUP BY los_group, diabetes
  UNION ALL
  SELECT 
    'AFib' AS comorbidity,
    los_group,
    afib AS has_comorbidity,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS deaths
  FROM cohort_with_comorbidities
  GROUP BY los_group, afib
  UNION ALL
  SELECT 
    'Hypertension' AS comorbidity,
    los_group,
    hypertension AS has_comorbidity,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS deaths
  FROM cohort_with_comorbidities
  GROUP BY los_group, hypertension
)
ORDER BY comorbidity, los_group, has_comorbidity DESC;