WITH heart_failure_adms AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code
   AND d.icd_version = dicd.icd_version
  WHERE LOWER(dicd.long_title) LIKE '%heart failure%'
),

-- Per-admission comorbidity counts and flags (exclude heart-failure codes from comorbidity count)
adm_comorbidity AS (
  SELECT
    d.hadm_id,
    COUNT(DISTINCT CASE
      WHEN LOWER(dicd.long_title) NOT LIKE '%heart failure%' THEN d.icd_code
      ELSE NULL END) AS comorbidity_count,
    MAX(CASE
      WHEN LOWER(dicd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS diabetes_flag,
    MAX(CASE
      WHEN (LOWER(dicd.long_title) LIKE '%chronic kidney%' 
            OR LOWER(dicd.long_title) LIKE '%chronic renal%' 
            OR LOWER(dicd.long_title) LIKE '%chronic kidney disease%' 
            OR LOWER(dicd.long_title) LIKE '%renal failure%' 
            OR LOWER(dicd.long_title) LIKE '%kidney failure%')
      THEN 1 ELSE 0 END) AS ckd_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code
   AND d.icd_version = dicd.icd_version
  WHERE d.hadm_id IN (SELECT hadm_id FROM heart_failure_adms)
  GROUP BY d.hadm_id
),

-- Base admissions filtered to cohort with computed per-admission fields
base_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    IF(i.hadm_id IS NOT NULL, TRUE, FALSE) AS icu_exists,
    COALESCE(ac.comorbidity_count, 0) AS comorbidity_count,
    COALESCE(ac.diabetes_flag, 0) AS diabetes_flag,
    COALESCE(ac.ckd_flag, 0) AS ckd_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- mark ICU existence using distinct hadm_id to avoid row duplication
  LEFT JOIN (
    SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) i
    ON a.hadm_id = i.hadm_id
  LEFT JOIN adm_comorbidity ac
    ON a.hadm_id = ac.hadm_id
  WHERE a.hadm_id IN (SELECT hadm_id FROM heart_failure_adms)
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)

SELECT
  CASE WHEN icu_exists THEN 'ICU' ELSE 'Non-ICU' END AS location,
  CASE WHEN los_days < 8 THEN '<8' ELSE '>=8' END AS los_group,
  CASE
    WHEN comorbidity_count <= 1 THEN '0-1'
    WHEN comorbidity_count = 2 THEN '2'
    ELSE '>=3'
  END AS comorbidity_bucket,
  COUNT(*) AS n_admissions,
  100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_percent,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  100.0 * SUM(ckd_flag) / COUNT(*) AS ckd_percent,
  100.0 * SUM(diabetes_flag) / COUNT(*) AS diabetes_percent
FROM base_admissions
GROUP BY
  icu_exists,
  CASE WHEN los_days < 8 THEN '<8' ELSE '>=8' END,
  CASE
    WHEN comorbidity_count <= 1 THEN '0-1'
    WHEN comorbidity_count = 2 THEN '2'
    ELSE '>=3'
  END
ORDER BY location, los_group, comorbidity_bucket;