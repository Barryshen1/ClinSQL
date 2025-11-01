WITH sepsis_admissions AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND (LOWER(dicd.long_title) LIKE '%sepsis%'
         AND LOWER(dicd.long_title) NOT LIKE '%shock%'
         AND LOWER(dicd.long_title) NOT LIKE '%septic shock%')
),
comorbidities AS (
  SELECT
    sa.subject_id,
    sa.hadm_id,
    sa.hospital_expire_flag,
    sa.los_days,
    MAX(CASE WHEN LOWER(dicd.long_title) LIKE '%chronic kidney%' OR LOWER(dicd.long_title) LIKE '%ckd%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN LOWER(dicd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN LOWER(dicd.long_title) LIKE '%atrial fibrillation%' OR LOWER(dicd.long_title) LIKE '%afib%' THEN 1 ELSE 0 END) AS has_afib,
    MAX(CASE WHEN LOWER(dicd.long_title) LIKE '%hypertension%' THEN 1 ELSE 0 END) AS has_hypertension
  FROM sepsis_admissions sa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON sa.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  GROUP BY sa.subject_id, sa.hadm_id, sa.hospital_expire_flag, sa.los_days
)
SELECT
  CASE WHEN los_days <= 5 THEN '≤5 days' ELSE '>5 days' END AS los_group,
  has_ckd,
  has_diabetes,
  has_afib,
  has_hypertension,
  COUNT(*) AS n_patients,
  SUM(hospital_expire_flag) AS n_deaths,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent
FROM comorbidities
GROUP BY los_group, has_ckd, has_diabetes, has_afib, has_hypertension
ORDER BY los_group, has_ckd, has_diabetes, has_afib, has_hypertension;