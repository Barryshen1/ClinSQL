WITH icu_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
cohort AS (
  SELECT
    a.hadm_id,
    -- ICU flag (1 if patient had ICU stay, 0 otherwise)
    CASE WHEN i.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS icu_flag,
    -- Hospital LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_hospital,
    -- In-hospital mortality flag
    a.hospital_expire_flag,
    -- CKD flag (using ICD-10 codes starting with N18)
    MAX(CASE WHEN d.icd_version = 10 AND d.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS ckd_flag,
    -- Diabetes flag (using ICD-10 codes E08-E13)
    MAX(CASE WHEN d.icd_version = 10 AND 
                  (d.icd_code LIKE 'E08%' OR 
                   d.icd_code LIKE 'E09%' OR 
                   d.icd_code LIKE 'E10%' OR 
                   d.icd_code LIKE 'E11%' OR 
                   d.icd_code LIKE 'E13%') THEN 1 ELSE 0 END) AS diabetes_flag,
    -- Comorbidity score (simplified version with 5 conditions)
    COALESCE(MAX(CASE WHEN d.icd_version = 10 AND 
                         (d.icd_code LIKE 'E08%' OR d.icd_code LIKE 'E09%' OR 
                          d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR 
                          d.icd_code LIKE 'E13%') THEN 1 ELSE 0 END), 0) +
    COALESCE(MAX(CASE WHEN d.icd_version = 10 AND d.icd_code LIKE 'N18%' THEN 1 ELSE 0 END), 0) +
    COALESCE(MAX(CASE WHEN d.icd_version = 10 AND 
                         (d.icd_code LIKE 'I10%' OR d.icd_code LIKE 'I11%' OR 
                          d.icd_code LIKE 'I12%' OR d.icd_code LIKE 'I13%' OR 
                          d.icd_code LIKE 'I15%') THEN 1 ELSE 0 END), 0) +
    COALESCE(MAX(CASE WHEN d.icd_version = 10 AND d.icd_code LIKE 'I50%' THEN 1 ELSE 0 END), 0) +
    COALESCE(MAX(CASE WHEN d.icd_version = 10 AND d.icd_code LIKE 'J44%' THEN 1 ELSE 0 END), 0) AS comorbidity_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN icu_admissions i
    ON a.hadm_id = i.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 52 AND 62
    AND a.dischtime IS NOT NULL
  GROUP BY a.hadm_id, icu_flag, los_hospital, hospital_expire_flag
),
cohort_with_tertile AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY comorbidity_score) AS comorbidity_tertile
  FROM cohort
)
SELECT
  icu_flag,
  CASE WHEN los_hospital <= 5 THEN '≤5' ELSE '>5' END AS los_group,
  comorbidity_tertile,
  COUNT(*) AS n,
  AVG(hospital_expire_flag) * 100 AS mortality_rate,
  AVG(ckd_flag) * 100 AS ckd_prevalence,
  AVG(diabetes_flag) * 100 AS diabetes_prevalence
FROM cohort_with_tertile
GROUP BY icu_flag, los_group, comorbidity_tertile
ORDER BY icu_flag, los_group, comorbidity_tertile;