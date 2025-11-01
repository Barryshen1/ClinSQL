WITH base AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE a.dischtime IS NOT NULL
    AND p.gender = 'M'
),
base_with_age AS (
  SELECT 
    *,
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_adm
  FROM base
),
cohort AS (
  SELECT 
    hadm_id,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
    hospital_expire_flag
  FROM base_with_age
  WHERE age_at_adm BETWEEN 68 AND 78
),
ckd AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND (icd_code LIKE '585%' OR icd_code IN ('V451','V560','V561','V568','V569')))
    OR
    (icd_version = 10 AND (icd_code LIKE 'N18%' OR icd_code = 'Z992'))
),
diabetes AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '250%')
    OR
    (icd_version = 10 AND (icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%'))
),
combined AS (
  SELECT
    c.hadm_id,
    c.los_days,
    c.hospital_expire_flag,
    IF(ckd.hadm_id IS NOT NULL, 1, 0) AS ckd_flag,
    IF(diabetes.hadm_id IS NOT NULL, 1, 0) AS diabetes_flag
  FROM cohort c
  LEFT JOIN ckd ON c.hadm_id = ckd.hadm_id
  LEFT JOIN diabetes ON c.hadm_id = diabetes.hadm_id
)
SELECT
  CASE WHEN los_days < 8 THEN '<8' ELSE '>=8' END AS los_group,
  COUNT(*) AS total_admissions,
  AVG(hospital_expire_flag) * 100 AS mortality_pct,
  AVG(ckd_flag) * 100 AS ckd_pct,
  AVG(diabetes_flag) * 100 AS diabetes_pct
FROM combined
GROUP BY los_group
ORDER BY los_group;