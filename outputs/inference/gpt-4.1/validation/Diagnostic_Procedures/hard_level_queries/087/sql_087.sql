WITH ich_icd_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%intracerebral hemorrhage%'
     OR LOWER(long_title) LIKE '%intracranial hemorrhage%'
     OR LOWER(long_title) LIKE '%subarachnoid hemorrhage%'
     OR LOWER(long_title) LIKE '%cerebral hemorrhage%'
     OR LOWER(long_title) LIKE '%brain hemorrhage%'
     OR LOWER(long_title) LIKE '%hemorrhage%'
     -- Add more terms if needed for completeness
)

-- Step 2: Get cohort ICU stays (female, age 56-66, with ICH diagnosis)
, cohort_icustays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 56 AND 66
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      INNER JOIN ich_icd_codes ich
        ON diag.icd_code = ich.icd_code AND diag.icd_version = ich.icd_version
      WHERE diag.hadm_id = icu.hadm_id
    )
)

-- Step 3: Diagnostic intensity per ICU stay (count distinct ICD codes for hadm_id)
, cohort_diag_intensity AS (
  SELECT
    c.stay_id,
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT diag.icd_code) AS diagnostic_intensity
  FROM cohort_icustays c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON c.hadm_id = diag.hadm_id
  GROUP BY c.stay_id, c.subject_id, c.hadm_id
)

-- Step 4: 95th percentile of diagnostic intensity in cohort
, cohort_diag_percentile AS (
  SELECT
    APPROX_QUANTILES(diagnostic_intensity, 100)[95] AS diagnostic_intensity_95th
  FROM cohort_diag_intensity
)

-- Step 5: ICU LOS and in-hospital mortality for cohort
, cohort_los_mortality AS (
  SELECT
    COUNT(*) AS n_cohort,
    APPROX_QUANTILES(c.los, 2)[OFFSET(1)] AS median_icu_los,
    AVG(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_mortality_rate
  FROM cohort_icustays c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.hadm_id = a.hadm_id
)

-- Step 6: ICU LOS and in-hospital mortality for all ICU patients
, all_icu_los_mortality AS (
  SELECT
    COUNT(*) AS n_all_icu,
    APPROX_QUANTILES(icu.los, 2)[OFFSET(1)] AS median_icu_los,
    AVG(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_mortality_rate
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.hadm_id = a.hadm_id
)

-- Final output
SELECT
  diag_percentile.diagnostic_intensity_95th AS cohort_95th_percentile_diagnostic_intensity,
  cohort_los_mortality.n_cohort,
  cohort_los_mortality.median_icu_los AS cohort_median_icu_los,
  cohort_los_mortality.in_hospital_mortality_rate AS cohort_in_hospital_mortality_rate,
  all_icu_los_mortality.n_all_icu,
  all_icu_los_mortality.median_icu_los AS all_icu_median_icu_los,
  all_icu_los_mortality.in_hospital_mortality_rate AS all_icu_in_hospital_mortality_rate
FROM cohort_diag_percentile diag_percentile
CROSS JOIN cohort_los_mortality
CROSS JOIN all_icu_los_mortality;