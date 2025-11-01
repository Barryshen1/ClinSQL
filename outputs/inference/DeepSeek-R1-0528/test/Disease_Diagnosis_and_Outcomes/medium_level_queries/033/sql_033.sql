WITH base_cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
),
complication_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r"^996|^997|^998|^999")) 
    OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r"^T8[0-8]"))
),
cohort AS (
  SELECT 
    b.*,
    DATE_DIFF(b.dischtime, b.admittime, DAY) AS los_days,
    CASE 
      WHEN i.hadm_id IS NOT NULL THEN 'ICU' 
      ELSE 'non-ICU' 
    END AS icu_status
  FROM base_cohort b
  INNER JOIN complication_admissions c 
    ON b.hadm_id = c.hadm_id
  LEFT JOIN (
    SELECT DISTINCT hadm_id 
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) i ON b.hadm_id = i.hadm_id
),
comorbidity_counts AS (
  SELECT 
    hadm_id, 
    COUNT(DISTINCT CONCAT(icd_code, '_', CAST(icd_version AS STRING))) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
final_cohort AS (
  SELECT 
    c.*,
    COALESCE(cc.comorbidity_count, 0) AS comorbidity_count,
    CASE 
      WHEN COALESCE(cc.comorbidity_count, 0) <= 1 THEN '0-1'
      WHEN COALESCE(cc.comorbidity_count, 0) = 2 THEN '2'
      ELSE '>=3'
    END AS comorbidity_bin
  FROM cohort c
  LEFT JOIN comorbidity_counts cc 
    ON c.hadm_id = cc.hadm_id
)
SELECT 
  icu_status,
  CASE 
    WHEN los_days <= 5 THEN '<=5' 
    ELSE '>5' 
  END AS los_group,
  comorbidity_bin,
  COUNT(DISTINCT hadm_id) AS N,
  ROUND(100 * AVG(hospital_expire_flag), 2) AS in_hospital_mortality_percent,
  ROUND(AVG(comorbidity_count), 2) AS avg_comorbidity_count
FROM final_cohort
GROUP BY icu_status, los_group, comorbidity_bin
ORDER BY icu_status, los_group, comorbidity_bin;