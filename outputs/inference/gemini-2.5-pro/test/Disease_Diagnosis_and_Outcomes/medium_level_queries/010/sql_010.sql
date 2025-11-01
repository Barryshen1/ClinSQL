WITH ami_hadm_ids AS (
  -- Find all hospital admissions with a diagnosis of Acute Myocardial Infarction (AMI)
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-9 codes for AMI
    (icd_version = 9 AND icd_code LIKE '410%')
    -- ICD-10 codes for AMI
    OR (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
),
exclusion_hadm_ids AS (
  -- Find all hospital admissions with a diagnosis of shock or respiratory failure for exclusion
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-9 and ICD-10 codes for Shock
    (icd_version = 9 AND icd_code LIKE '785.5%') OR (icd_version = 10 AND (icd_code LIKE 'R57%' OR icd_code LIKE 'R65.2%'))
    -- ICD-9 and ICD-10 codes for Respiratory Failure
    OR (icd_version = 9 AND icd_code IN ('518.81', '518.82', '518.84', '799.1'))
    OR (icd_version = 10 AND (icd_code LIKE 'J96%' OR icd_code = 'R09.2'))
),
base_cohort AS (
  -- Construct the primary cohort based on inclusion/exclusion criteria and demographics
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  -- Must be an AMI admission
  INNER JOIN ami_hadm_ids AS ami ON adm.hadm_id = ami.hadm_id
  -- Must NOT be an admission with shock or respiratory failure
  LEFT JOIN exclusion_hadm_ids AS ex ON adm.hadm_id = ex.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 78 AND 88
    AND ex.hadm_id IS NULL -- Apply the exclusion
    AND adm.dischtime IS NOT NULL AND adm.admittime IS NOT NULL -- Ensure LOS can be calculated
),
cohort_with_metrics AS (
  -- Add comorbidity scores, LOS quartiles, and specific disease flags
  SELECT
    b.hadm_id,
    b.hospital_expire_flag,
    -- Define comorbidity burden category based on the Elixhauser Van Walraven score
    CASE
      WHEN elix.elixhauser_vanwalraven <= 1 THEN 'Low (0-1)'
      WHEN elix.elixhauser_vanwalraven BETWEEN 2 AND 4 THEN 'Medium (2-4)'
      WHEN elix.elixhauser_vanwalraven >= 5 THEN 'High (5+)'
    END AS comorbidity_burden,
    -- Divide patients into LOS quartiles
    NTILE(4) OVER (ORDER BY b.los) AS los_quartile,
    -- Create flags for CKD and Diabetes from Elixhauser components
    elix.renal_failure AS has_ckd,
    (CASE WHEN elix.diabetes_uncomplicated = 1 OR elix.diabetes_complicated = 1 THEN 1 ELSE 0 END) AS has_diabetes
  FROM base_cohort AS b
  -- Join with the pre-calculated Elixhauser comorbidity scores table
  INNER JOIN `physionet-data.mimiciv_derived.elixhauser` AS elix
    ON b.hadm_id = elix.hadm_id
),
aggregated_stats AS (
  -- Aggregate counts by the defined strata
  SELECT
    comorbidity_burden,
    los_quartile,
    COUNT(*) AS n_patients,
    SUM(hospital_expire_flag) AS n_deaths,
    SUM(has_ckd) AS n_ckd,
    SUM(has_diabetes) AS n_diabetes
  FROM cohort_with_metrics
  WHERE comorbidity_burden IS NOT NULL -- Exclude if score was not calculated
  GROUP BY comorbidity_burden, los_quartile
)
-- Final report generation with all requested metrics
SELECT
  agg.comorbidity_burden,
  agg.los_quartile,
  agg.n_patients,
  -- In-hospital mortality rate
  ROUND(SAFE_DIVIDE(agg.n_deaths, agg.n_patients), 4) AS in_hospital_mortality_rate,
  -- 95% CI for mortality using the Wilson score interval method
  CASE
    WHEN agg.n_patients = 0 THEN NULL
    ELSE
      LET(
        p_hat = SAFE_DIVIDE(agg.n_deaths, agg.n_patients),
        n = agg.n_patients,
        z = 1.96,
        CONCAT(
          '[',
          CAST(ROUND(
            SAFE_DIVIDE( (p_hat + z*z/(2*n)) - z * SQRT( (p_hat*(1-p_hat))/n + z*z/(4*n*n) ), (1 + z*z/n) )
          , 4) AS STRING),
          ', ',
          CAST(ROUND(
            SAFE_DIVIDE( (p_hat + z*z/(2*n)) + z * SQRT( (p_hat*(1-p_hat))/n + z*z/(4*n*n) ), (1 + z*z/n) )
          , 4) AS STRING),
          ']'
        )
      )
  END AS mortality_rate_95_ci,
  -- Prevalence of CKD and Diabetes
  ROUND(SAFE_DIVIDE(agg.n_ckd, agg.n_patients), 4) AS ckd_prevalence,
  ROUND(SAFE_DIVIDE(agg.n_diabetes, agg.n_patients), 4) AS diabetes_prevalence
FROM aggregated_stats AS agg
ORDER BY
  -- Order logically by comorbidity burden, then by LOS quartile
  CASE
    WHEN agg.comorbidity_burden = 'Low (0-1)' THEN 1
    WHEN agg.comorbidity_burden = 'Medium (2-4)' THEN 2
    WHEN agg.comorbidity_burden = 'High (5+)' THEN 3
  END,
  agg.los_quartile;