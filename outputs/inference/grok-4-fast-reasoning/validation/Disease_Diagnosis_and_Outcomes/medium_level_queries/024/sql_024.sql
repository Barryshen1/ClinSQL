WITH sepsis_adm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND (icd_code LIKE '038.%' OR icd_code = '995.91'))
     OR (icd_version = 10 AND (icd_code LIKE 'A41%' OR icd_code = 'R65.20'))
),
shock_adm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code = '785.52')
     OR (icd_version = 10 AND icd_code = 'R65.21')
),
valid_adm AS (
  SELECT hadm_id
  FROM sepsis_adm
  WHERE hadm_id NOT IN (SELECT hadm_id FROM shock_adm)
),
ckd_adm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND (icd_code LIKE '585%' OR icd_code = '586'))
     OR (icd_version = 10 AND icd_code LIKE 'N18%')
),
diabetes_adm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '250%')
     OR (icd_version = 10 AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%'))
),
first_icu AS (
  SELECT i.hadm_id, MIN(TIMESTAMP_DIFF(i.intime, a.admittime, HOUR)) AS first_icu_hours
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a USING (hadm_id)
  GROUP BY i.hadm_id
),
cohort AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN f.first_icu_hours IS NULL OR f.first_icu_hours > 24 THEN 0 
      ELSE 1 
    END AS day1_icu_flag,
    CASE WHEN c.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS ckd_flag,
    CASE WHEN d.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS diabetes_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN valid_adm va ON a.hadm_id = va.hadm_id
  LEFT JOIN first_icu f ON a.hadm_id = f.hadm_id
  LEFT JOIN ckd_adm c ON a.hadm_id = c.hadm_id
  LEFT JOIN diabetes_adm d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F' 
    AND p.anchor_age >= 49 
    AND p.anchor_age <= 59
)
SELECT 
  CASE WHEN los_days <= 5 THEN '<=5' ELSE '>5' END AS los_group,
  CASE WHEN day1_icu_flag = 1 THEN 'day-1 ICU' ELSE 'non-ICU' END AS day1_group,
  COUNT(*) AS N,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
  ROUND(AVG(ckd_flag) * 100, 2) AS ckd_pct,
  ROUND(AVG(diabetes_flag) * 100, 2) AS diabetes_pct
FROM cohort
GROUP BY los_group, day1_group
ORDER BY los_group, day1_group;