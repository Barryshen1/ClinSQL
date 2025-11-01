WITH
  -- Step 1: Calculate a comorbidity score for each hospital admission based on ICD codes.
  -- This is a simplified Elixhauser comorbidity index.
  comorbidity_scores AS (
    SELECT
      hadm_id,
      -- Sum of flags for various chronic diseases
      (
        MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('401', '402', '403', '404', '405')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I10', 'I11', 'I12', 'I13', 'I15')) THEN 1 ELSE 0 END) -- Hypertension
        + MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '428') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I50') THEN 1 ELSE 0 END) -- Congestive Heart Failure
        + MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '250') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('E08', 'E09', 'E10', 'E11', 'E13')) THEN 1 ELSE 0 END) -- Diabetes
        + MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('585', '586')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('N18', 'N19')) THEN 1 ELSE 0 END) -- Renal Failure
        + MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '490' AND '496') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'J40' AND 'J47') THEN 1 ELSE 0 END) -- Chronic Pulmonary Disease
        + MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '140' AND '239') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 1) = 'C') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'D00' AND 'D49') THEN 1 ELSE 0 END) -- Cancer (Malignant and In Situ)
      ) AS comorbidity_count
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
  ),

  -- Step 2: Identify the primary cohort of female stroke patients aged 48-58
  stroke_admissions AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'F'
      -- Calculate age at admission and filter
      AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 48 AND 58
      -- Filter for admissions with a stroke diagnosis using a subquery
      AND a.hadm_id IN (
        SELECT DISTINCT dx.hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
          ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
        WHERE
          -- Broad search for cerebrovascular diseases, plus specific ICD ranges for stroke
          LOWER(d_dx.long_title) LIKE '%cerebrovascular disease%'
          OR (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN '430' AND '438')
          OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN 'I60' AND 'I69')
      )
  ),

  -- Step 3: Combine the cohort with stratification variables
  analysis_cohort AS (
    SELECT
      sa.hadm_id,
      sa.hospital_expire_flag,
      -- ICU vs. Non-ICU status
      CASE WHEN icu.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
      -- Length of stay (LOS) category
      CASE
        WHEN DATETIME_DIFF(sa.dischtime, sa.admittime, DAY) <= 5 THEN 'LOS <= 5 days'
        ELSE 'LOS > 5 days'
      END AS los_category,
      -- Comorbidity burden category
      CASE
        WHEN COALESCE(cs.comorbidity_count, 0) = 0 THEN '0 comorbidities'
        WHEN COALESCE(cs.comorbidity_count, 0) BETWEEN 1 AND 2 THEN '1-2 comorbidities'
        ELSE '3+ comorbidities'
      END AS comorbidity_burden
    FROM stroke_admissions AS sa
    -- Join to get comorbidity score
    LEFT JOIN comorbidity_scores AS cs
      ON sa.hadm_id = cs.hadm_id
    -- Join to check for an ICU stay; use DISTINCT to prevent row duplication for multi-stay admissions
    LEFT JOIN (
      SELECT DISTINCT hadm_id, stay_id FROM `physionet-data.mimiciv_3_1_icu.icustays`
    ) AS icu
      ON sa.hadm_id = icu.hadm_id
  )

-- Step 4: Final aggregation to calculate mortality and CIs for each stratum
SELECT
  icu_status,
  los_category,
  comorbidity_burden,
  COUNT(*) AS total_admissions,
  SUM(hospital_expire_flag) AS total_deaths,
  -- Mortality rate (%)
  AVG(hospital_expire_flag) * 100 AS mortality_percent,
  -- 95% CI lower bound
  (
    AVG(hospital_expire_flag) - 1.96 * SQRT(
      SAFE_DIVIDE(
        AVG(hospital_expire_flag) * (1 - AVG(hospital_expire_flag)),
        COUNT(*)
      )
    )
  ) * 100 AS lower_ci_95,
  -- 95% CI upper bound
  (
    AVG(hospital_expire_flag) + 1.96 * SQRT(
      SAFE_DIVIDE(
        AVG(hospital_expire_flag) * (1 - AVG(hospital_expire_flag)),
        COUNT(*)
      )
    )
  ) * 100 AS upper_ci_95
FROM analysis_cohort
GROUP BY
  icu_status,
  los_category,
  comorbidity_burden
ORDER BY
  icu_status DESC,
  los_category,
  comorbidity_burden;