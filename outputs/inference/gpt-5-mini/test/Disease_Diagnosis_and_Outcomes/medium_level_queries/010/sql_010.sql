WITH diagnoses_with_text AS (
  SELECT
    d.hadm_id,
    d.icd_code,
    CAST(d.icd_version AS STRING) AS icd_version,
    dd.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND CAST(d.icd_version AS STRING) = CAST(dd.icd_version AS STRING)
),

-- Aggregate per admission: comorbidity flags and exclusion flags
diag_flags AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN LOWER(long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS flag_diabetes,
    MAX(CASE WHEN LOWER(long_title) LIKE '%chronic kidney%' OR LOWER(long_title) LIKE '%chronic renal%' OR LOWER(long_title) LIKE '%ckd%' OR LOWER(long_title) LIKE '%renal failure, chronic%' THEN 1 ELSE 0 END) AS flag_ckd,
    MAX(CASE WHEN LOWER(long_title) LIKE '%heart failure%' OR LOWER(long_title) LIKE '%congestive heart failure%' THEN 1 ELSE 0 END) AS flag_hf,
    MAX(CASE WHEN LOWER(long_title) LIKE '%hypertension%' THEN 1 ELSE 0 END) AS flag_htn,
    MAX(CASE WHEN LOWER(long_title) LIKE '%chronic obstructive pulmonary%' OR LOWER(long_title) LIKE '%emphysema%' OR LOWER(long_title) LIKE '%chronic bronchitis%' THEN 1 ELSE 0 END) AS flag_copd,
    MAX(CASE WHEN LOWER(long_title) LIKE '%dementia%' OR LOWER(long_title) LIKE '%alzheimer%' THEN 1 ELSE 0 END) AS flag_dementia,
    MAX(CASE WHEN LOWER(long_title) LIKE '%malign%' OR LOWER(long_title) LIKE '%neoplasm%' OR LOWER(long_title) LIKE '%metasta%' THEN 1 ELSE 0 END) AS flag_cancer,
    MAX(CASE WHEN LOWER(long_title) LIKE '%liver%' OR LOWER(long_title) LIKE '%cirrhosis%' THEN 1 ELSE 0 END) AS flag_liver,
    MAX(CASE WHEN LOWER(long_title) LIKE '%peripheral vascular%' OR LOWER(long_title) LIKE '%atherosclero%' OR LOWER(long_title) LIKE '%peripheral arterial%' THEN 1 ELSE 0 END) AS flag_pvd,
    MAX(CASE WHEN LOWER(long_title) LIKE '%cerebrovascular%' OR LOWER(long_title) LIKE '%stroke%' OR LOWER(long_title) LIKE '%hemiplegia%' THEN 1 ELSE 0 END) AS flag_cvd,
    -- Exclusionary acute conditions
    MAX(CASE WHEN LOWER(long_title) LIKE '%shock%' THEN 1 ELSE 0 END) AS flag_shock,
    MAX(CASE WHEN LOWER(long_title) LIKE '%respiratory failure%' OR LOWER(long_title) LIKE '%respiratory insufficiency%' OR LOWER(long_title) LIKE '%acute respiratory%' THEN 1 ELSE 0 END) AS flag_resp_failure,
    -- Also mark presence of AMI for inclusion check
    MAX(CASE WHEN LOWER(long_title) LIKE '%acute myocardial%' OR LOWER(long_title) LIKE '%acute mi%' OR LOWER(long_title) LIKE '%myocardial infarct%' THEN 1 ELSE 0 END) AS flag_ami
  FROM diagnoses_with_text
  GROUP BY hadm_id
),

-- Admissions of interest: male, age 78-88 inclusive, AMI present, exclude shock/resp fail, completed admission
cohort_base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    -- LOS in days (fractional)
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE), 1440.0) AS los_days,
    COALESCE(df.flag_diabetes, 0) AS flag_diabetes,
    COALESCE(df.flag_ckd, 0) AS flag_ckd,
    COALESCE(df.flag_hf, 0) AS flag_hf,
    COALESCE(df.flag_htn, 0) AS flag_htn,
    COALESCE(df.flag_copd, 0) AS flag_copd,
    COALESCE(df.flag_dementia, 0) AS flag_dementia,
    COALESCE(df.flag_cancer, 0) AS flag_cancer,
    COALESCE(df.flag_liver, 0) AS flag_liver,
    COALESCE(df.flag_pvd, 0) AS flag_pvd,
    COALESCE(df.flag_cvd, 0) AS flag_cvd
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN diag_flags df
    ON a.hadm_id = df.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND COALESCE(df.flag_ami, 0) = 1                -- admission has AMI diagnosis
    AND COALESCE(df.flag_shock, 0) = 0              -- exclude shock
    AND COALESCE(df.flag_resp_failure, 0) = 0       -- exclude respiratory failure
    AND a.dischtime IS NOT NULL
),

-- Compute comorbidity count and bucket and LOS quartile
cohort_enriched AS (
  SELECT
    cb.*,
    -- Sum of chronic comorbidity flags (we include diabetes and ckd among others)
    (flag_diabetes + flag_ckd + flag_hf + flag_htn + flag_copd + flag_dementia + flag_cancer + flag_liver + flag_pvd + flag_cvd) AS comorbidity_count,
    CASE
      WHEN (flag_diabetes + flag_ckd + flag_hf + flag_htn + flag_copd + flag_dementia + flag_cancer + flag_liver + flag_pvd + flag_cvd) <= 1 THEN 'low'
      WHEN (flag_diabetes + flag_ckd + flag_hf + flag_htn + flag_copd + flag_dementia + flag_cancer + flag_liver + flag_pvd + flag_cvd) BETWEEN 2 AND 3 THEN 'medium'
      ELSE 'high'
    END AS comorbidity_burden,
    -- LOS quartile across the cohort (1 = shortest LOS)
    NTILE(4) OVER (ORDER BY SAFE_CAST(SAFE_DIVIDE(TIMESTAMP_DIFF(dischtime, admittime, MINUTE), 1440.0) AS FLOAT64)) AS los_quartile
  FROM cohort_base cb
)

-- Final aggregation: mortality and CKD/diabetes prevalence by LOS quartile and comorbidity_burden
SELECT
  los_quartile,
  comorbidity_burden,
  COUNT(1) AS n_admissions,
  SUM(CAST(hospital_expire_flag AS INT64)) AS n_deaths,
  -- mortality percent
  ROUND(100.0 * SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS FLOAT64)), COUNT(1)), 2) AS mortality_pct,
  -- 95% CI (Wald): p +/- 1.96*sqrt(p*(1-p)/n), clamped to [0,100]
  CASE WHEN COUNT(1) > 0 THEN
    ROUND(100.0 * GREATEST(0.0,
      SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS FLOAT64)), COUNT(1))
      - 1.96 * SQRT(
          SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS FLOAT64)), COUNT(1)) *
          (1 - SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS FLOAT64)), COUNT(1)))
          / COUNT(1)
        )
    ), 2)
  ELSE NULL END AS mortality_ci_lower_pct,
  CASE WHEN COUNT(1) > 0 THEN
    ROUND(100.0 * LEAST(1.0,
      SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS FLOAT64)), COUNT(1))
      + 1.96 * SQRT(
          SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS FLOAT64)), COUNT(1)) *
          (1 - SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS FLOAT64)), COUNT(1)))
          / COUNT(1)
        )
    ), 2)
  ELSE NULL END AS mortality_ci_upper_pct,
  -- CKD prevalence in this cell (percent)
  ROUND(100.0 * SAFE_DIVIDE(SUM(flag_ckd), COUNT(1)), 2) AS ckd_prev_pct,
  -- Diabetes prevalence in this cell (percent)
  ROUND(100.0 * SAFE_DIVIDE(SUM(flag_diabetes), COUNT(1)), 2) AS diabetes_prev_pct
FROM cohort_enriched
GROUP BY los_quartile, comorbidity_burden
ORDER BY los_quartile, CASE comorbidity_burden WHEN 'low' THEN 1 WHEN 'medium' THEN 2 WHEN 'high' THEN 3 END;