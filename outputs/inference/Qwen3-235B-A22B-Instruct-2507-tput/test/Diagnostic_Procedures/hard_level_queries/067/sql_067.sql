WITH heart_failure_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%heart failure%'
     OR icd_code LIKE 'I50%' -- ICD-10 codes for heart failure
),
hf_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON p.subject_id = di.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 70 AND 80
    AND di.icd_version = 10
    AND di.icd_code IN (SELECT icd_code FROM heart_failure_codes)
),
icu_stays_with_los_death AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ie.hadm_id = a.hadm_id
),
diagnostic_events AS (
  -- Lab events
  SELECT
    le.hadm_id,
    le.charttime,
    'lab' AS event_type
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  WHERE le.charttime IS NOT NULL
  UNION ALL
  -- Microbiology events
  SELECT
    me.hadm_id,
    me.charttime,
    'micro' AS event_type
  FROM `physionet-data.mimiciv_3_1_hosp.microbiologyevents` me
  WHERE me.charttime IS NOT NULL
),
icu_diagnostics AS (
  SELECT
    ics.stay_id,
    ics.subject_id,
    ics.hadm_id,
    ics.intime,
    ics.los,
    ics.hospital_expire_flag,
    COUNT(de.charttime) AS diagnostic_count_72h
  FROM icu_stays_with_los_death ics
  LEFT JOIN diagnostic_events de
    ON ics.hadm_id = de.hadm_id
    AND de.charttime >= ics.intime
    AND de.charttime <= DATETIME_ADD(ics.intime, INTERVAL 72 HOUR)
  GROUP BY ics.stay_id, ics.subject_id, ics.hadm_id, ics.intime, ics.los, ics.hospital_expire_flag
),
hf_icu_diagnostics AS (
  SELECT id.*
  FROM icu_diagnostics id
  INNER JOIN hf_patients hf
    ON id.subject_id = hf.subject_id
),
summary_stats AS (
  SELECT
    'Heart Failure Males 70-80' AS cohort,
    AVG(diagnostic_count_72h) AS mean_diagnostic_intensity,
    APPROX_QUANTILES(diagnostic_count_72h, 1000)[OFFSET(500)] AS median_diagnostic_intensity,
    APPROX_QUANTILES(diagnostic_count_72h, 1000)[OFFSET(750)] AS p75_diagnostic_intensity,
    APPROX_QUANTILES(diagnostic_count_72h, 1000)[OFFSET(950)] AS p95_diagnostic_intensity,
    AVG(los) AS mean_icu_los,
    AVG(hospital_expire_flag) AS hospital_mortality_rate
  FROM hf_icu_diagnostics
  UNION ALL
  SELECT
    'All ICU Patients' AS cohort,
    AVG(diagnostic_count_72h) AS mean_diagnostic_intensity,
    APPROX_QUANTILES(diagnostic_count_72h, 1000)[OFFSET(500)] AS median_diagnostic_intensity,
    APPROX_QUANTILES(diagnostic_count_72h, 1000)[OFFSET(750)] AS p75_diagnostic_intensity,
    APPROX_QUANTILES(diagnostic_count_72h, 1000)[OFFSET(950)] AS p95_diagnostic_intensity,
    AVG(los) AS mean_icu_los,
    AVG(hospital_expire_flag) AS hospital_mortality_rate
  FROM icu_diagnostics
)
SELECT
  cohort,
  ROUND(mean_diagnostic_intensity, 2) AS mean_diagnostic_intensity,
  median_diagnostic_intensity,
  p75_diagnostic_intensity,
  p95_diagnostic_intensity,
  ROUND(mean_icu_los, 2) AS mean_icu_los,
  ROUND(hospital_mortality_rate, 3) AS hospital_mortality_rate
FROM summary_stats
ORDER BY cohort;