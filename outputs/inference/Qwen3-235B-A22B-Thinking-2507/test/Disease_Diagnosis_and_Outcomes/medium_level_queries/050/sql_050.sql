WITH sepsis_candidates AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN (icd_version = 10 AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%')) 
              OR (icd_version = 9 AND icd_code LIKE '038%') THEN 1 ELSE 0 END) AS has_sepsis,
    MAX(CASE WHEN (icd_version = 10 AND icd_code = 'R6521') 
              OR (icd_version = 9 AND icd_code = '78552') THEN 1 ELSE 0 END) AS has_shock
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
sepsis_no_shock AS (
  SELECT hadm_id
  FROM sepsis_candidates
  WHERE has_sepsis = 1 AND has_shock = 0
),
comorbidity_flags AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN (icd_version = 10 AND icd_code LIKE 'N18%') OR (icd_version = 9 AND icd_code LIKE '585%') THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN (icd_version = 10 AND (icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%')) 
               OR (icd_version = 9 AND icd_code LIKE '250%') THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN (icd_version = 10 AND icd_code LIKE 'I48%') 
               OR (icd_version = 9 AND icd_code LIKE '4273%') THEN 1 ELSE 0 END) AS has_afib,
    MAX(CASE WHEN (icd_version = 10 AND icd_code = 'I10') 
               OR (icd_version = 9 AND icd_code LIKE '401%') THEN 1 ELSE 0 END) AS has_hypertension
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
)
SELECT
  los_group,
  has_ckd,
  has_diabetes,
  has_afib,
  has_hypertension,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate_percent
FROM (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag,
    CASE WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) <= 5 THEN '≤5' ELSE '>5' END AS los_group,
    COALESCE(cf.has_ckd, 0) AS has_ckd,
    COALESCE(cf.has_diabetes, 0) AS has_diabetes,
    COALESCE(cf.has_afib, 0) AS has_afib,
    COALESCE(cf.has_hypertension, 0) AS has_hypertension
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN sepsis_no_shock sns
    ON a.hadm_id = sns.hadm_id
  LEFT JOIN comorbidity_flags cf
    ON a.hadm_id = cf.hadm_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 75 AND 85
) base
GROUP BY los_group, has_ckd, has_diabetes, has_afib, has_hypertension
ORDER BY los_group, has_ckd, has_diabetes, has_afib, has_hypertension;