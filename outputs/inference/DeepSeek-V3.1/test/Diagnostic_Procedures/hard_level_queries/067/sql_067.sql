WITH hf_codes AS (
  -- ICD-9 and ICD-10 codes for heart failure
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 10 AND icd_code LIKE 'I50%') OR
    (icd_version = 9 AND icd_code IN ('4280', '4281', '4282', '4283', '4284', '4289'))
),

target_cohort AS (
  SELECT DISTINCT
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id,
    COUNT(DISTINCT le.itemid) AS num_labs_72h
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON ie.hadm_id = diag.hadm_id
  INNER JOIN hf_codes
    ON diag.icd_code = hf_codes.icd_code 
    AND diag.icd_version = hf_codes.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ie.hadm_id = le.hadm_id
    AND le.charttime >= ie.intime
    AND le.charttime < DATETIME_ADD(ie.intime, INTERVAL 72 HOUR)
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 70 AND 80
  GROUP BY ie.stay_id, ie.subject_id, ie.hadm_id
),

general_cohort AS (
  SELECT 
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id,
    COUNT(DISTINCT le.itemid) AS num_labs_72h
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ie.hadm_id = le.hadm_id
    AND le.charttime >= ie.intime
    AND le.charttime < DATETIME_ADD(ie.intime, INTERVAL 72 HOUR)
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 70 AND 80
  GROUP BY ie.stay_id, ie.subject_id, ie.hadm_id
),

target_aggregates AS (
  SELECT
    'Heart Failure Cohort' AS cohort,
    COUNT(*) AS n_stays,
    AVG(num_labs_72h) AS mean_diag_intensity,
    APPROX_QUANTILES(num_labs_72h, 100)[OFFSET(50)] AS median_diag_intensity,
    APPROX_QUANTILES(num_labs_72h, 100)[OFFSET(75)] AS p75_diag_intensity,
    APPROX_QUANTILES(num_labs_72h, 100)[OFFSET(95)] AS p95_diag_intensity,
    AVG(ie.los) AS mean_icu_los,
    AVG(adm.hospital_expire_flag) AS hospital_mortality
  FROM target_cohort tc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
    ON tc.stay_id = ie.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON tc.hadm_id = adm.hadm_id
),

general_aggregates AS (
  SELECT
    'General ICU Population' AS cohort,
    COUNT(*) AS n_stays,
    AVG(num_labs_72h) AS mean_diag_intensity,
    APPROX_QUANTILES(num_labs_72h, 100)[OFFSET(50)] AS median_diag_intensity,
    APPROX_QUANTILES(num_labs_72h, 100)[OFFSET(75)] AS p75_diag_intensity,
    APPROX_QUANTILES(num_labs_72h, 100)[OFFSET(95)] AS p95_diag_intensity,
    AVG(ie.los) AS mean_icu_los,
    AVG(adm.hospital_expire_flag) AS hospital_mortality
  FROM general_cohort gc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
    ON gc.stay_id = ie.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON gc.hadm_id = adm.hadm_id
)

SELECT * FROM target_aggregates
UNION ALL
SELECT * FROM general_aggregates;