WITH sepsis_admissions AS (
  SELECT 
    a.hadm_id,
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 75 AND 85
),
sepsis_diagnoses AS (
  SELECT 
    di.hadm_id,
    MAX(CASE WHEN di.icd_code IN ('A419', 'A418', 'R6520') AND di.icd_version = 10 THEN 1 ELSE 0 END) AS has_sepsis,
    MAX(CASE WHEN di.icd_code = 'R6521' AND di.icd_version = 10 THEN 1 ELSE 0 END) AS has_septic_shock
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  GROUP BY di.hadm_id
),
comorbidities AS (
  SELECT 
    di.hadm_id,
    MAX(CASE WHEN di.icd_version = 10 AND di.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN di.icd_version = 10 AND di.icd_code LIKE 'E1%' THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN di.icd_version = 10 AND di.icd_code LIKE 'I48%' THEN 1 ELSE 0 END) AS has_afib,
    MAX(CASE WHEN di.icd_version = 10 AND di.icd_code LIKE 'I1%' THEN 1 ELSE 0 END) AS has_hypertension
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  GROUP BY di.hadm_id
),
cohort AS (
  SELECT 
    sa.hadm_id,
    sa.hospital_expire_flag,
    sa.los_days,
    c.has_ckd,
    c.has_diabetes,
    c.has_afib,
    c.has_hypertension
  FROM sepsis_admissions sa
  JOIN sepsis_diagnoses s ON sa.hadm_id = s.hadm_id
  JOIN comorbidities c ON sa.hadm_id = c.hadm_id
  WHERE s.has_sepsis = 1
    AND s.has_septic_shock = 0
)
SELECT
  CASE WHEN los_days <= 5 THEN '≤5 days' ELSE '>5 days' END AS los_group,
  has_ckd,
  has_diabetes,
  has_afib,
  has_hypertension,
  COUNT(*) AS n,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_rate_pct
FROM cohort
GROUP BY los_group, has_ckd, has_diabetes, has_afib, has_hypertension
ORDER BY los_group, has_ckd, has_diabetes, has_afib, has_hypertension;