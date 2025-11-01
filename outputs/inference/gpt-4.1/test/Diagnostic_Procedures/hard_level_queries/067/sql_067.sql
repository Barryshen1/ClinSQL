WITH
-- Heart failure ICD codes (ICD-9: 428*, ICD-10: I50*)
heart_failure_icd AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND icd_code LIKE '428%')
    OR (icd_version = 10 AND icd_code LIKE 'I50%')
),

-- ICU stays for male patients aged 70-80
icu_patients AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pat.gender,
    pat.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.anchor_age BETWEEN 70 AND 80 AND pat.gender = 'M'
),

-- Heart failure ICU stays (male, 70-80, with HF diagnosis)
hf_icu_stays AS (
  SELECT DISTINCT icu.*
  FROM icu_patients icu
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON icu.subject_id = dx.subject_id AND icu.hadm_id = dx.hadm_id
  JOIN heart_failure_icd hf
    ON dx.icd_code = hf.icd_code AND dx.icd_version = hf.icd_version
),

-- All ICU stays (general population)
all_icu_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
),

-- Diagnostic events in first 72h for HF cohort
hf_diag_events AS (
  SELECT
    s.stay_id,
    COUNT(DISTINCT l.labevent_id) AS lab_count,
    COUNT(DISTINCT m.microevent_id) AS micro_count
  FROM hf_icu_stays s
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON s.subject_id = l.subject_id
    AND s.hadm_id = l.hadm_id
    AND l.charttime >= s.intime
    AND l.charttime < TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` m
    ON s.subject_id = m.subject_id
    AND s.hadm_id = m.hadm_id
    AND m.charttime >= s.intime
    AND m.charttime < TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
  GROUP BY s.stay_id
),

-- Diagnostic events in first 72h for general ICU cohort
all_diag_events AS (
  SELECT
    s.stay_id,
    COUNT(DISTINCT l.labevent_id) AS lab_count,
    COUNT(DISTINCT m.microevent_id) AS micro_count
  FROM all_icu_stays s
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON s.subject_id = l.subject_id
    AND s.hadm_id = l.hadm_id
    AND l.charttime >= s.intime
    AND l.charttime < TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` m
    ON s.subject_id = m.subject_id
    AND s.hadm_id = m.hadm_id
    AND m.charttime >= s.intime
    AND m.charttime < TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
  GROUP BY s.stay_id
),

-- Add LOS and hospital mortality for HF cohort
hf_final AS (
  SELECT
    s.stay_id,
    COALESCE(e.lab_count, 0) + COALESCE(e.micro_count, 0) AS diag_intensity,
    s.los,
    a.hospital_expire_flag
  FROM hf_icu_stays s
  LEFT JOIN hf_diag_events e ON s.stay_id = e.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.subject_id = a.subject_id AND s.hadm_id = a.hadm_id
),

-- Add LOS and hospital mortality for general ICU cohort
all_final AS (
  SELECT
    s.stay_id,
    COALESCE(e.lab_count, 0) + COALESCE(e.micro_count, 0) AS diag_intensity,
    s.los,
    a.hospital_expire_flag
  FROM all_icu_stays s
  LEFT JOIN all_diag_events e ON s.stay_id = e.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.subject_id = a.subject_id AND s.hadm_id = a.hadm_id
)

-- Final output: summary statistics for both cohorts
SELECT
  'Heart Failure, Male, 70-80' AS cohort,
  COUNT(*) AS n_stays,
  ROUND(AVG(diag_intensity), 2) AS mean_diag_intensity,
  ROUND(APPROX_QUANTILES(diag_intensity, 2)[OFFSET(1)], 2) AS median_diag_intensity,
  ROUND(APPROX_QUANTILES(diag_intensity, 4)[OFFSET(3)], 2) AS p75_diag_intensity,
  ROUND(APPROX_QUANTILES(diag_intensity, 20)[OFFSET(19)], 2) AS p95_diag_intensity,
  ROUND(AVG(los), 2) AS mean_icu_los,
  ROUND(100 * AVG(CAST(hospital_expire_flag AS FLOAT64)), 2) AS hospital_mortality_pct
FROM hf_final

UNION ALL

SELECT
  'General ICU' AS cohort,
  COUNT(*) AS n_stays,
  ROUND(AVG(diag_intensity), 2) AS mean_diag_intensity,
  ROUND(APPROX_QUANTILES(diag_intensity, 2)[OFFSET(1)], 2) AS median_diag_intensity,
  ROUND(APPROX_QUANTILES(diag_intensity, 4)[OFFSET(3)], 2) AS p75_diag_intensity,
  ROUND(APPROX_QUANTILES(diag_intensity, 20)[OFFSET(19)], 2) AS p95_diag_intensity,
  ROUND(AVG(los), 2) AS mean_icu_los,
  ROUND(100 * AVG(CAST(hospital_expire_flag AS FLOAT64)), 2) AS hospital_mortality_pct
FROM all_final;