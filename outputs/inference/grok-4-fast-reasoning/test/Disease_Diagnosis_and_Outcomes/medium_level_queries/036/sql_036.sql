WITH admission_comorb AS (
  SELECT 
    subject_id, 
    hadm_id,
    COUNT(*) AS num_diagnoses,
    LOGICAL_OR(
      (icd_version = 9 AND icd_code LIKE '428%') OR 
      (icd_version = 10 AND icd_code LIKE 'I50%')
    ) AS has_hf,
    LOGICAL_OR(
      (icd_version = 9 AND icd_code LIKE '250%') OR 
      (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E(10|11|12|13|14)'))
    ) AS has_dm,
    LOGICAL_OR(
      (icd_version = 9 AND (icd_code LIKE '585%' OR icd_code LIKE '586%')) OR 
      (icd_version = 10 AND icd_code LIKE 'N18%')
    ) AS has_ckd
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY subject_id, hadm_id
),
cohort AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag,
    ac.num_diagnoses,
    ac.has_dm,
    ac.has_ckd,
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  LEFT JOIN admission_comorb ac ON a.subject_id = ac.subject_id AND a.hadm_id = ac.hadm_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 39 AND 49 
    AND ac.has_hf = TRUE
),
cohort_with_groups AS (
  SELECT 
    *,
    CASE 
      WHEN los_days <= 5 THEN '≤5' 
      ELSE '>5' 
    END AS los_group
  FROM cohort
),
cohort_with_tertile AS (
  SELECT 
    *,
    NTILE(3) OVER (ORDER BY num_diagnoses ASC) AS tertile_num
  FROM cohort_with_groups
)
SELECT 
  los_group,
  CASE 
    WHEN tertile_num = 1 THEN 'Low'
    WHEN tertile_num = 2 THEN 'Med' 
    WHEN tertile_num = 3 THEN 'High'
  END AS comorb_tertile,
  COUNT(*) AS N,
  SAFE_DIVIDE(
    COUNT(CASE WHEN hospital_expire_flag = 1 THEN 1 END) * 100.0, 
    COUNT(*)
  ) AS mortality_pct,
  SAFE_DIVIDE(
    SUM(CASE WHEN has_ckd = TRUE THEN 1 ELSE 0 END) * 100.0, 
    COUNT(*)
  ) AS ckd_prevalence_pct,
  SAFE_DIVIDE(
    SUM(CASE WHEN has_dm = TRUE THEN 1 ELSE 0 END) * 100.0, 
    COUNT(*)
  ) AS diabetes_prevalence_pct
FROM cohort_with_tertile
GROUP BY los_group, tertile_num
ORDER BY los_group, tertile_num;