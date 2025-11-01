WITH sepsis_adms AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE ((icd_version = 10 AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%' OR icd_code = 'R65.20'))
         OR (icd_version = 9 AND (icd_code LIKE '038%' OR icd_code = '99591')))
),

septic_shock_adms AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 10 AND icd_code = 'R65.21')
     OR (icd_version = 9 AND icd_code = '78552')
),

cohort_adms AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN sepsis_adms s ON a.hadm_id = s.hadm_id
  LEFT JOIN septic_shock_adms ss ON a.hadm_id = ss.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND ss.hadm_id IS NULL
    AND a.dischtime IS NOT NULL
),

ckd_adms AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 10 AND icd_code LIKE 'N18%')
     OR (icd_version = 9 AND icd_code LIKE '585%')
),

dm_adms AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE ((icd_version = 10 AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E12%' 
                                  OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%')))
     OR (icd_version = 9 AND (icd_code LIKE '249%' OR icd_code LIKE '250%'))
),

cohort_with_conditions AS (
  SELECT 
    c.*,
    CASE WHEN ck.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_ckd,
    CASE WHEN dm.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_dm
  FROM cohort_adms c
  LEFT JOIN ckd_adms ck ON c.hadm_id = ck.hadm_id
  LEFT JOIN dm_adms dm ON c.hadm_id = dm.hadm_id
),

quartiles AS (
  SELECT *,
    NTILE(4) OVER (ORDER BY los_days ASC) AS los_quartile
  FROM cohort_with_conditions
)

SELECT 
  los_quartile AS quartile,
  COUNT(*) AS n_admissions,
  ROUND(AVG(hospital_expire_flag * 1.0), 3) AS mortality_rate,
  ROUND(AVG(has_ckd * 1.0), 3) AS ckd_prevalence,
  ROUND(AVG(has_dm * 1.0), 3) AS diabetes_prevalence
FROM quartiles
GROUP BY los_quartile
ORDER BY los_quartile;