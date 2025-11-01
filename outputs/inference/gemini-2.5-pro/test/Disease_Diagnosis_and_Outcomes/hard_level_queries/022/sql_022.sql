WITH
  -- Step 1: Identify all hospital admissions with a diagnosis of AKI
  aki_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      (icd_version = 9 AND icd_code LIKE '584%')
      OR (icd_version = 10 AND icd_code LIKE 'N17%')
  ),

  -- Step 2: Define the base cohort of female patients aged 40-50 with AKI
  cohort_base AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      p.dod,
      DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    INNER JOIN aki_admissions AS aki
      ON a.hadm_id = aki.hadm_id
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 40 AND 50
  ),

  -- Step 3: Calculate features based on diagnoses: ARDS flag and comorbidity count for the cohort
  diagnosis_features AS (
    SELECT
      hadm_id,
      MAX(
        CASE
          WHEN (icd_version = 9 AND icd_code = '518.82') OR (icd_version = 10 AND icd_code = 'J80')
            THEN 1
          ELSE 0
        END
      ) AS has_ards,
      COUNT(DISTINCT CASE
        WHEN
          NOT (
            (icd_version = 9 AND icd_code LIKE '584%') OR (icd_version = 10 AND icd_code LIKE 'N17%')
          )
          AND NOT (
            (icd_version = 9 AND icd_code = '518.82') OR (icd_version = 10 AND icd_code = 'J80')
          )
          THEN icd_code
      END) AS num_comorbidities
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE hadm_id IN (SELECT hadm_id FROM cohort_base)
    GROUP BY
      hadm_id
  ),

  -- Step 4: Combine cohort with features, calculate risk score and outcomes
  patient_risk AS (
    SELECT
      cb.hadm_id,
      cb.los_days,
      cb.hospital_expire_flag,
      COALESCE(df.has_ards, 0) AS has_ards,
      COALESCE(df.num_comorbidities, 0) AS num_comorbidities,
      -- Flag for 30-day post-discharge mortality
      CASE
        WHEN cb.dod IS NOT NULL AND DATETIME_DIFF(cb.dod, cb.dischtime, DAY) BETWEEN 1 AND 30
          THEN 1
        ELSE 0
      END AS mort_30d_post_discharge,
      -- Calculate the composite risk score
      (5 * COALESCE(df.num_comorbidities, 0)) + (50 * COALESCE(df.has_ards, 0)) AS composite_risk
    FROM cohort_base AS cb
    LEFT JOIN diagnosis_features AS df
      ON cb.hadm_id = df.hadm_id
  ),

  -- Step 5: Stratify patients into risk quintiles
  risk_quintiles AS (
    SELECT
      *,
      NTILE(5) OVER (ORDER BY composite_risk) AS risk_quintile
    FROM patient_risk
  )

-- Step 6: Final aggregation by quintile to report results
SELECT
  risk_quintile,
  COUNT(hadm_id) AS N,
  AVG(mort_30d_post_discharge) * 100 AS mortality_30d_post_discharge_pct,
  AVG(has_ards) * 100 AS ards_cooccurrence_pct,
  -- Calculate median LOS for survivors only
  APPROX_QUANTILES(
    CASE WHEN hospital_expire_flag = 0 THEN los_days END, 100
  )[OFFSET(50)] AS median_survivor_los_days
FROM risk_quintiles
GROUP BY
  risk_quintile
ORDER BY
  risk_quintile;