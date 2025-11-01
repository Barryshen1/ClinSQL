WITH stroke_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (
    (icd_version = 9 AND (
      icd_code LIKE '433%' OR icd_code LIKE '434%' OR icd_code = '436'
    ))
    OR
    (icd_version = 10 AND (
      icd_code LIKE 'I63%' OR icd_code LIKE 'I61%' OR icd_code = 'I64'
    ))
  )
),
stroke_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.hospital_expire_flag,
         pat.gender,
         -- calculate age at admission
         pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN stroke_codes sc
    ON diag.icd_code = sc.icd_code AND diag.icd_version = sc.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 48 AND 58
),
icu_flags AS (
  SELECT hadm_id, 1 AS icu_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
comorbidity_counts AS (
  SELECT di.hadm_id,
         COUNT(DISTINCT di.icd_code) AS comorb_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN stroke_codes sc
    ON di.icd_code = sc.icd_code AND di.icd_version = sc.icd_version
  WHERE sc.icd_code IS NULL  -- exclude stroke codes
  GROUP BY di.hadm_id
),
final_cohort AS (
  SELECT sa.hadm_id,
         sa.subject_id,
         sa.hospital_expire_flag,
         IFNULL(ic.icu_flag,0) AS icu_flag,
         CASE WHEN DATE_DIFF(sa.dischtime, sa.admittime, DAY) <= 5 THEN '<=5' ELSE '>5' END AS los_group,
         cc.comorb_count,
         CASE WHEN cc.comorb_count = 0 THEN '0'
              WHEN cc.comorb_count BETWEEN 1 AND 2 THEN '1-2'
              ELSE '>=3' END AS comorb_category
  FROM stroke_admissions sa
  LEFT JOIN icu_flags ic ON sa.hadm_id = ic.hadm_id
  LEFT JOIN comorbidity_counts cc ON sa.hadm_id = cc.hadm_id
)
SELECT
  icu_flag,
  los_group,
  comorb_category,
  COUNT(*) AS n_admissions,
  SUM(hospital_expire_flag) AS n_deaths,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 1) AS mortality_percent,
  ROUND(100 * (SUM(hospital_expire_flag) / COUNT(*) - 1.96 * SQRT((SUM(hospital_expire_flag) / COUNT(*)) * (1 - SUM(hospital_expire_flag) / COUNT(*)) / COUNT(*))), 1) AS ci_lower_percent,
  ROUND(100 * (SUM(hospital_expire_flag) / COUNT(*) + 1.96 * SQRT((SUM(hospital_expire_flag) / COUNT(*)) * (1 - SUM(hospital_expire_flag) / COUNT(*)) / COUNT(*))), 1) AS ci_upper_percent
FROM final_cohort
GROUP BY icu_flag, los_group, comorb_category
ORDER BY icu_flag DESC, los_group, comorb_category;