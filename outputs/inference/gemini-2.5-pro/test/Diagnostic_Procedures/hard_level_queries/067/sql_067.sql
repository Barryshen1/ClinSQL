WITH hf_admissions AS (
  -- Identify all hospital admissions with a heart failure diagnosis
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '428')
    OR
    (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I50')
),
all_diagnostics AS (
  -- Combine lab and microbiology events to define "diagnostic events"
  SELECT hadm_id, charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  UNION ALL
  SELECT hadm_id, COALESCE(charttime, DATETIME(chartdate)) AS charttime
  FROM `physionet-data.mimiciv_3_1_hosp.microbiologyevents`
),
cohort_base AS (
  -- Create a base cohort of all ICU stays with flags for the group of interest
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los,
    adm.hospital_expire_flag,
    CASE
      WHEN pat.gender = 'M' AND pat.anchor_age BETWEEN 70 AND 80 AND hf.hadm_id IS NOT NULL
      THEN TRUE
      ELSE FALSE
    END AS is_hf_cohort
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON icu.hadm_id = adm.hadm_id
  LEFT JOIN hf_admissions AS hf
    ON icu.hadm_id = hf.hadm_id
),
stay_diag_counts AS (
  -- Count the number of diagnostic events in the first 72 hours for each stay
  SELECT
    cb.stay_id,
    cb.los,
    cb.hospital_expire_flag,
    cb.is_hf_cohort,
    COUNT(diag.charttime) AS diagnostic_events_72h
  FROM cohort_base AS cb
  LEFT JOIN all_diagnostics AS diag
    ON cb.hadm_id = diag.hadm_id
    AND diag.charttime BETWEEN cb.intime AND DATETIME_ADD(cb.intime, INTERVAL 72 HOUR)
  GROUP BY
    cb.stay_id, cb.los, cb.hospital_expire_flag, cb.is_hf_cohort
)
-- Final aggregation for the HF cohort
SELECT
  'Male, 70-80, with Heart Failure' AS cohort,
  AVG(diagnostic_events_72h) AS mean_diagnostics_72h,
  APPROX_QUANTILES(diagnostic_events_72h, 100)[OFFSET(50)] AS median_diagnostics_72h,
  APPROX_QUANTILES(diagnostic_events_72h, 100)[OFFSET(75)] AS p75_diagnostics_72h,
  APPROX_QUANTILES(diagnostic_events_72h, 100)[OFFSET(95)] AS p95_diagnostics_72h,
  AVG(los) AS mean_icu_los_days,
  AVG(hospital_expire_flag) * 100 AS hospital_mortality_percent
FROM stay_diag_counts
WHERE is_hf_cohort = TRUE

UNION ALL

-- Final aggregation for the general ICU population
SELECT
  'General ICU Population' AS cohort,
  AVG(diagnostic_events_72h) AS mean_diagnostics_72h,
  APPROX_QUANTILES(diagnostic_events_72h, 100)[OFFSET(50)] AS median_diagnostics_72h,
  APPROX_QUANTILES(diagnostic_events_72h, 100)[OFFSET(75)] AS p75_diagnostics_72h,
  APPROX_QUANTILES(diagnostic_events_72h, 100)[OFFSET(95)] AS p95_diagnostics_72h,
  AVG(los) AS mean_icu_los_days,
  AVG(hospital_expire_flag) * 100 AS hospital_mortality_percent
FROM stay_diag_counts;