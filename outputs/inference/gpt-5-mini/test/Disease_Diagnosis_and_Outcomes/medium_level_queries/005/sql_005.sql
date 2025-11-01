WITH hf_hadm AS (
  -- Admissions that have a heart-failure diagnosis (by diagnosis long_title)
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%heart failure%'
),

comorb_counts AS (
  -- For each admission, count distinct diagnosis codes excluding diagnoses that are heart failure
  SELECT
    d.hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorb_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE d.hadm_id IN (SELECT hadm_id FROM hf_hadm)
    AND LOWER(dd.long_title) NOT LIKE '%heart failure%'  -- exclude HF codes from comorbidity count
  GROUP BY d.hadm_id
),

cohort AS (
  -- Admissions for male patients age 38-48 that have heart failure
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    -- LOS in days: count partial days as 1
    (TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1) AS los_days,
    -- ICU flag: any icustay for this hadm_id
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i WHERE i.hadm_id = a.hadm_id
    ) THEN 'ICU' ELSE 'No ICU' END AS icu_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
    AND a.hadm_id IN (SELECT hadm_id FROM hf_hadm)
),

cohort_with_comorb AS (
  SELECT
    c.*,
    COALESCE(cc.comorb_count, 0) AS comorb_count  -- if no non-HF diagnoses, 0
  FROM cohort c
  LEFT JOIN comorb_counts cc
    ON c.hadm_id = cc.hadm_id
),

aggregated AS (
  -- Aggregate counts and mean comorbidity per stratification
  SELECT
    icu_flag,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN los_days >= 8 THEN '>=8'
      ELSE '0'
    END AS los_bucket,
    CASE
      WHEN comorb_count <= 3 THEN '<=3'
      WHEN comorb_count BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_bucket,
    COUNT(1) AS n_admissions,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
    AVG(comorb_count) AS mean_comorbidity_count
  FROM cohort_with_comorb
  GROUP BY icu_flag, los_bucket, charlson_bucket
)

SELECT
  icu_flag,
  los_bucket,
  charlson_bucket,
  n_admissions,
  n_deaths,
  -- mortality percent
  SAFE_MULTIPLY(SAFE_DIVIDE(n_deaths, n_admissions), 100) AS mortality_pct,
  -- p_hat
  SAFE_DIVIDE(n_deaths, n_admissions) AS p_hat,
  -- standard error (normal approximation)
  CASE
    WHEN n_admissions > 0 THEN SQRT(SAFE_DIVIDE(SAFE_MULTIPLY(SAFE_DIVIDE(n_deaths, n_admissions), (1 - SAFE_DIVIDE(n_deaths, n_admissions))), n_admissions))
    ELSE NULL
  END AS se_p,
  -- 95% CI lower (percent)
  CASE
    WHEN n_admissions > 0 THEN
      GREATEST(0, SAFE_MULTIPLY((SAFE_DIVIDE(n_deaths, n_admissions) - 1.96 * SQRT(SAFE_DIVIDE(SAFE_MULTIPLY(SAFE_DIVIDE(n_deaths, n_admissions), (1 - SAFE_DIVIDE(n_deaths, n_admissions))), n_admissions))), 100))
    ELSE NULL
  END AS mortality_ci_lower_pct,
  -- 95% CI upper (percent)
  CASE
    WHEN n_admissions > 0 THEN
      LEAST(100, SAFE_MULTIPLY((SAFE_DIVIDE(n_deaths, n_admissions) + 1.96 * SQRT(SAFE_DIVIDE(SAFE_MULTIPLY(SAFE_DIVIDE(n_deaths, n_admissions), (1 - SAFE_DIVIDE(n_deaths, n_admissions))), n_admissions))), 100))
    ELSE NULL
  END AS mortality_ci_upper_pct,
  mean_comorbidity_count
FROM aggregated
ORDER BY icu_flag DESC, los_bucket, charlson_bucket;