WITH
  -- Define the initial cohort of female patients aged 74-84 with Pulmonary Embolism (PE)
  FemalePECohort AS (
    SELECT
      adm.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime,
      adm.hospital_expire_flag,
      pat.gender,
      pat.anchor_age
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON adm.hadm_id = di.hadm_id
    WHERE
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 74 AND 84
      -- ICD-9 codes for Pulmonary Embolism: 415.1x
      -- ICD-10 codes for Pulmonary Embolism: I26.x
      AND (
          (di.icd_version = 9 AND di.icd_code LIKE '415.1%')
          OR (di.icd_version = 10 AND di.icd_code LIKE 'I26%')
          )
    GROUP BY -- Group to ensure each admission appears once, even if multiple PE ICD codes are present
      adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.hospital_expire_flag, pat.gender, pat.anchor_age
  ),

  -- Illustrative list of QT-prolonging drugs. (In a real scenario, this would come from a comprehensive drug database.)
  QTDrugs AS (
    SELECT 'Amiodarone' AS drug_name UNION ALL
    SELECT 'Sotalol' UNION ALL
    SELECT 'Ciprofloxacin' UNION ALL
    SELECT 'Azithromycin' UNION ALL
    SELECT 'Ondansetron' UNION ALL
    SELECT 'Haloperidol'
  ),

  -- Illustrative list of Bleeding risk drugs. (In a real scenario, this would come from a comprehensive drug database.)
  BleedingRiskDrugs AS (
    SELECT 'Warfarin' AS drug_name UNION ALL
    SELECT 'Heparin' UNION ALL
    SELECT 'Enoxaparin' UNION ALL
    SELECT 'Aspirin' UNION ALL -- Note: Aspirin dosage/context can differentiate antiplatelet vs. bleeding risk
    SELECT 'Clopidogrel'
  ),

  -- Retrieve all medications prescribed within the first 24 hours of admission for the cohort
  CohortMedications AS (
    SELECT
      fpc.subject_id,
      fpc.hadm_id,
      pres.drug -- The reported drug name
    FROM
      FemalePECohort fpc
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
      ON fpc.subject_id = pres.subject_id AND fpc.hadm_id = pres.hadm_id
    WHERE
      pres.starttime BETWEEN fpc.admittime AND DATETIME_ADD(fpc.admittime, INTERVAL 24 HOUR)
      AND pres.drug IS NOT NULL AND TRIM(pres.drug) != '' -- Exclude invalid drug entries
  ),

  -- Aggregate medication data and other admission-level statistics for each admission in the cohort
  AdmissionStats AS (
    SELECT
      fpc.subject_id,
      fpc.hadm_id,
      fpc.admittime,
      fpc.dischtime,
      fpc.hospital_expire_flag,
      -- Calculate Length of Stay (LOS) in days. Handle cases where dischtime might be null or before admittime.
      CASE
        WHEN fpc.dischtime IS NOT NULL AND fpc.dischtime > fpc.admittime
        THEN DATETIME_DIFF(fpc.dischtime, fpc.admittime, HOUR) / 24.0
        ELSE NULL
      END AS los_days,
      -- Count distinct medications for each admission within the first 24 hours
      COUNT(DISTINCT cm.drug) AS distinct_med_count_24hr,
      -- Flag if any QT-prolonging drug was administered
      MAX(CASE WHEN qd.drug_name IS NOT NULL THEN 1 ELSE 0 END) AS has_qt_prolonging_drug_24hr,
      -- Flag if any bleeding-risk drug was administered
      MAX(CASE WHEN brd.drug_name IS NOT NULL THEN 1 ELSE 0 END) AS has_bleeding_risk_drug_24hr,
      -- Determine if the admission included an ICU stay
      CASE
        WHEN EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` icu WHERE icu.hadm_id = fpc.hadm_id AND icu.subject_id = fpc.subject_id)
        THEN 1 ELSE 0
      END AS had_icu_stay
    FROM
      FemalePECohort fpc
    LEFT JOIN
      CohortMedications cm
      ON fpc.hadm_id = cm.hadm_id
    LEFT JOIN
      QTDrugs qd
      ON LOWER(cm.drug) = LOWER(qd.drug_name) -- Fix: Use LOWER() for case-insensitive comparison
    LEFT JOIN
      BleedingRiskDrugs brd
      ON LOWER(cm.drug) = LOWER(brd.drug_name) -- Fix: Use LOWER() for case-insensitive comparison
    GROUP BY
      fpc.subject_id, fpc.hadm_id, fpc.admittime, fpc.dischtime, fpc.hospital_expire_flag
  ),

  -- Calculate medication complexity percentiles for the admissions
  ComplexityStats AS (
    SELECT
      *,
      -- Calculate percentile rank for distinct medication count (higher count = higher percentile)
      PERCENT_RANK() OVER (ORDER BY distinct_med_count_24hr) * 100 AS med_complexity_percentile
    FROM
      AdmissionStats
  ),

  -- Calculate the 75th percentile for Length of Stay (LOS) across the entire study cohort
  LOSPercentiles AS (
    SELECT
      PERCENTILE_CONT(0.75) OVER() AS los_75th_percentile
    FROM
      ComplexityStats
    WHERE los_days IS NOT NULL -- Exclude admissions with missing or invalid LOS from this calculation
    QUALIFY ROW_NUMBER() OVER() = 1 -- Ensure only one row is returned for the percentile
  )

-- The final SELECT statement performs all requested aggregations and presents results
SELECT
    "### Cohort Overview ###" AS section,
    COUNT(DISTINCT cs.hadm_id) AS total_admissions_in_cohort,

    "### Medication Complexity (First 24 hrs, Overall) ###" AS section_med_complexity_overall,
    AVG(cs.distinct_med_count_24hr) AS mean_med_complexity_24hr,
    MIN(cs.distinct_med_count_24hr) AS min_med_complexity_24hr,
    MAX(cs.distinct_med_count_24hr) AS max_med_complexity_24hr,
    STDDEV(cs.distinct_med_count_24hr) AS stddev_med_complexity_24hr,

    "### Drug Prevalence (First 24 hrs, Overall) ###" AS section_drug_prevalence_overall,
    SAFE_DIVIDE(SUM(cs.has_qt_prolonging_drug_24hr), COUNT(DISTINCT cs.hadm_id)) AS prevalence_qt_prolonging_drugs_24hr,
    SAFE_DIVIDE(SUM(cs.has_bleeding_risk_drug_24hr), COUNT(DISTINCT cs.hadm_id)) AS prevalence_bleeding_risk_drugs_24hr,

    "### Mean Complexity Percentiles (Overall) ###" AS section_complexity_percentiles_overall,
    AVG(cs.med_complexity_percentile) AS mean_med_complexity_percentile,

    "### ICU Comparison (Medication Complexity & Drug Prevalence) ###" AS section_icu_comparison,
    -- ICU Patients
    COUNT(DISTINCT CASE WHEN cs.had_icu_stay = 1 THEN cs.hadm_id END) AS num_icu_admissions,
    AVG(CASE WHEN cs.had_icu_stay = 1 THEN cs.distinct_med_count_24hr END) AS mean_med_complexity_24hr_icu,
    MIN(CASE WHEN cs.had_icu_stay = 1 THEN cs.distinct_med_count_24hr END) AS min_med_complexity_24hr_icu,
    MAX(CASE WHEN cs.had_icu_stay = 1 THEN cs.distinct_med_count_24hr END) AS max_med_complexity_24hr_icu,
    STDDEV(CASE WHEN cs.had_icu_stay = 1 THEN cs.distinct_med_count_24hr END) AS stddev_med_complexity_24hr_icu,
    SAFE_DIVIDE(SUM(CASE WHEN cs.had_icu_stay = 1 THEN cs.has_qt_prolonging_drug_24hr ELSE 0 END), SUM(CASE WHEN cs.had_icu_stay = 1 THEN 1 ELSE 0 END)) AS prevalence_qt_prolonging_icu,
    SAFE_DIVIDE(SUM(CASE WHEN cs.had_icu_stay = 1 THEN cs.has_bleeding_risk_drug_24hr ELSE 0 END), SUM(CASE WHEN cs.had_icu_stay = 1 THEN 1 ELSE 0 END)) AS prevalence_bleeding_risk_icu,
    AVG(CASE WHEN cs.had_icu_stay = 1 THEN cs.med_complexity_percentile END) AS mean_med_complexity_percentile_icu,

    -- Non-ICU Patients
    COUNT(DISTINCT CASE WHEN cs.had_icu_stay = 0 THEN cs.hadm_id END) AS num_non_icu_admissions,
    AVG(CASE WHEN cs.had_icu_stay = 0 THEN cs.distinct_med_count_24hr END) AS mean_med_complexity_24hr_non_icu,
    MIN(CASE WHEN cs.had_icu_stay = 0 THEN cs.distinct_med_count_24hr END) AS min_med_complexity_24hr_non_icu,
    MAX(CASE WHEN cs.had_icu_stay = 0 THEN cs.distinct_med_count_24hr END) AS max_med_complexity_24hr_non_icu,
    STDDEV(CASE WHEN cs.had_icu_stay = 0 THEN cs.distinct_med_count_24hr END) AS stddev_med_complexity_24hr_non_icu,
    SAFE_DIVIDE(SUM(CASE WHEN cs.had_icu_stay = 0 THEN cs.has_qt_prolonging_drug_24hr ELSE 0 END), SUM(CASE WHEN cs.had_icu_stay = 0 THEN 1 ELSE 0 END)) AS prevalence_qt_prolonging_non_icu,
    SAFE_DIVIDE(SUM(CASE WHEN cs.had_icu_stay = 0 THEN cs.has_bleeding_risk_drug_24hr ELSE 0 END), SUM(CASE WHEN cs.had_icu_stay = 0 THEN 1 ELSE 0 END)) AS prevalence_bleeding_risk_non_icu,
    AVG(CASE WHEN cs.had_icu_stay = 0 THEN cs.med_complexity_percentile END) AS mean_med_complexity_percentile_non_icu,

    "### Top-quartile LOS and Mortality ###" AS section_los_mortality,
    lp.los_75th_percentile AS los_75th_percentile_overall, -- los_75th_percentile is a single scalar value from the LOSPercentiles CTE
    SAFE_DIVIDE(
        SUM(CASE WHEN cs.los_days IS NOT NULL AND cs.los_days >= lp.los_75th_percentile THEN cs.hospital_expire_flag ELSE 0 END),
        SUM(CASE WHEN cs.los_days IS NOT NULL AND cs.los_days >= lp.los_75th_percentile THEN 1 ELSE 0 END)
    ) AS mortality_rate_in_top_quartile_los
FROM
    ComplexityStats cs
CROSS JOIN
    LOSPercentiles lp; -- Cross join the single row from LOSPercentiles;