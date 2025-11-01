WITH
-- Define heart failure ICD codes (I50.* for HF)
heart_failure_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'I50.%'
),

-- Define AKI ICD codes (N17.* for AKI)
aki_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'N17.%'
),

-- Define ARDS ICD codes (J80 for ARDS)
ards_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code = 'J80'
),

-- Get female patients aged 59-69 with HF
hf_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.deathtime, a.admittime, HOUR) AS survival_hours
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN heart_failure_codes hf ON d.icd_code = hf.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
),

-- Identify AKI cases
aki_cases AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN aki_codes a ON d.icd_code = a.icd_code
),

-- Identify ARDS cases
ards_cases AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN ards_codes a ON d.icd_code = a.icd_code
),

-- Calculate SOFA score components (simplified)
sofa_components AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    -- Glasgow Coma Scale (GCS) - using first available
    MAX(CASE WHEN di.label = 'GCS Total' THEN ce.valuenum ELSE NULL END) AS gcs,
    -- Platelets
    MAX(CASE WHEN di.label = 'Platelet Count' THEN ce.valuenum ELSE NULL END) AS platelets,
    -- Bilirubin
    MAX(CASE WHEN di.label = 'Bilirubin' THEN ce.valuenum ELSE NULL END) AS bilirubin,
    -- Creatinine or urine output
    MAX(CASE WHEN di.label = 'Creatinine' THEN ce.valuenum ELSE NULL END) AS creatinine,
    -- Vasopressors (using norepinephrine as proxy)
    MAX(CASE WHEN di.label = 'Norepinephrine' THEN ce.valuenum ELSE NULL END) AS norepinephrine
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE ce.hadm_id IN (SELECT hadm_id FROM hf_patients)
  GROUP BY ce.subject_id, ce.hadm_id
),

-- Calculate simplified SOFA score
sofa_scores AS (
  SELECT
    subject_id,
    hadm_id,
    -- Simplified SOFA score calculation (0-24 scale)
    (CASE
      WHEN gcs IS NULL OR platelets IS NULL OR bilirubin IS NULL OR creatinine IS NULL THEN NULL
      ELSE
        (CASE WHEN gcs >= 15 THEN 0 WHEN gcs BETWEEN 13 AND 14 THEN 1 WHEN gcs BETWEEN 10 AND 12 THEN 2 WHEN gcs BETWEEN 6 AND 9 THEN 3 ELSE 4 END) +
        (CASE WHEN platelets >= 150 THEN 0 WHEN platelets BETWEEN 100 AND 149 THEN 1 WHEN platelets BETWEEN 50 AND 99 THEN 2 WHEN platelets BETWEEN 20 AND 49 THEN 3 ELSE 4 END) +
        (CASE WHEN bilirubin < 1.2 THEN 0 WHEN bilirubin BETWEEN 1.2 AND 1.9 THEN 1 WHEN bilirubin BETWEEN 2.0 AND 5.9 THEN 2 WHEN bilirubin BETWEEN 6.0 AND 11.9 THEN 3 ELSE 4 END) +
        (CASE WHEN creatinine < 1.2 THEN 0 WHEN creatinine BETWEEN 1.2 AND 1.9 THEN 1 WHEN creatinine BETWEEN 2.0 AND 3.4 THEN 2 WHEN creatinine BETWEEN 3.5 AND 4.9 THEN 3 ELSE 4 END) +
        (CASE WHEN norepinephrine IS NULL OR norepinephrine = 0 THEN 0 ELSE 2 END)
    END) AS sofa_score
  FROM sofa_components
)

-- Final results
SELECT
  -- In-hospital mortality
  COUNT(CASE WHEN hospital_expire_flag = 1 THEN 1 END) AS in_hospital_deaths,
  COUNT(*) AS total_patients,
  ROUND(COUNT(CASE WHEN hospital_expire_flag = 1 THEN 1 END) / COUNT(*), 4) AS mortality_rate,

  -- AKI rate
  COUNT(DISTINCT CASE WHEN a.hadm_id IN (SELECT hadm_id FROM aki_cases) THEN a.hadm_id END) AS aki_cases,
  ROUND(COUNT(DISTINCT CASE WHEN a.hadm_id IN (SELECT hadm_id FROM aki_cases) THEN a.hadm_id END) / COUNT(*), 4) AS aki_rate,

  -- ARDS rate
  COUNT(DISTINCT CASE WHEN a.hadm_id IN (SELECT hadm_id FROM ards_cases) THEN a.hadm_id END) AS ards_cases,
  ROUND(COUNT(DISTINCT CASE WHEN a.hadm_id IN (SELECT hadm_id FROM ards_cases) THEN a.hadm_id END) / COUNT(*), 4) AS ards_rate,

  -- Median survival among in-hospital deaths
  APPROX_QUANTILES(IF(hospital_expire_flag = 1, survival_hours, NULL), 100)[OFFSET(50)] AS median_survival_hours,

  -- SOFA score distribution
  MIN(sofa_score) AS sofa_min,
  APPROX_QUANTILES(sofa_score, 100)[OFFSET(25)] AS sofa_p25,
  APPROX_QUANTILES(sofa_score, 100)[OFFSET(50)] AS sofa_median,
  APPROX_QUANTILES(sofa_score, 100)[OFFSET(75)] AS sofa_p75,
  APPROX_QUANTILES(sofa_score, 100)[OFFSET(90)] AS sofa_p90,
  MAX(sofa_score) AS sofa_max

FROM hf_patients a
LEFT JOIN sofa_scores s ON a.hadm_id = s.hadm_id;