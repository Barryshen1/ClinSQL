WITH 
-- Define CCI mapping (simplified; must be expanded with all Charlson conditions and ICD-10 codes)
cci_codes AS (
  SELECT 
    icd_code,
    condition,
    weight
  FROM UNNEST([
    STRUCT('I21.0' AS icd_code, 'Myocardial infarction' AS condition, 1 AS weight),
    STRUCT('I21.1', 'Myocardial infarction', 1),
    STRUCT('I21.2', 'Myocardial infarction', 1),
    STRUCT('I21.3', 'Myocardial infarction', 1),
    STRUCT('I21.4', 'Myocardial infarction', 1),
    STRUCT('I50.9', 'Congestive heart failure', 1),
    STRUCT('I50.10', 'Congestive heart failure', 1),
    STRUCT('I50.11', 'Congestive heart failure', 1),
    STRUCT('I50.12', 'Congestive heart failure', 1),
    STRUCT('I50.13', 'Congestive heart failure', 1),
    STRUCT('I50.20', 'Congestive heart failure', 1),
    STRUCT('I50.21', 'Congestive heart failure', 1),
    STRUCT('I50.22', 'Congestive heart failure', 1),
    STRUCT('I50.30', 'Congestive heart failure', 1),
    STRUCT('I50.31', 'Congestive heart failure', 1),
    STRUCT('I50.32', 'Congestive heart failure', 1),
    STRUCT('I50.40', 'Congestive heart failure', 1),
    STRUCT('I50.41', 'Congestive heart failure', 1),
    STRUCT('I50.42', 'Congestive heart failure', 1),
    STRUCT('I50.90', 'Congestive heart failure', 1),
    STRUCT('I50.91', 'Congestive heart failure', 1),
    STRUCT('I50.92', 'Congestive heart failure', 1),
    STRUCT('I50.93', 'Congestive heart failure', 1),
    -- Add other Charlson conditions here (e.g., peripheral vascular disease, cerebrovascular disease, etc.)
    -- Note: DVT is not part of Charlson, so we exclude it in the next CTE
  ])
),
-- DVT diagnosis codes (ICD-10)
dvt_codes AS (
  SELECT 'D64.9' AS icd_code
  UNION ALL SELECT 'D64.0'
  UNION ALL SELECT 'D64.1'
  UNION ALL SELECT 'D64.2'
  UNION ALL SELECT 'D64.3'
  UNION ALL SELECT 'D64.4'
  UNION ALL SELECT 'D64.5'
  UNION ALL SELECT 'D64.6'
  UNION ALL SELECT 'D64.7'
  UNION ALL SELECT 'D64.8'
  UNION ALL SELECT 'D64.9'
),
-- Patient diagnoses (all ICD-10)
patient_diagnoses AS (
  SELECT 
    d.subject_id,
    d.icd_code,
    d.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_version = 10
),
-- Map diagnoses to CCI conditions, excluding DVT
patient_conditions AS (
  SELECT 
    pd.subject_id,
    cci.condition,
    MAX(cci.weight) AS weight
  FROM patient_diagnoses pd
  JOIN cci_codes cci
    ON pd.icd_code = cci.icd_code
  WHERE cci.condition != 'DVT'  -- exclude DVT from CCI
  GROUP BY pd.subject_id, cci.condition
),
-- Compute CCI per patient
patient_cci AS (
  SELECT 
    subject_id,
    SUM(weight) AS cci
  FROM patient_conditions
  GROUP BY subject_id
),
-- Admissions with age and gender
admissions_with_age AS (
  SELECT 
    a.*,
    p.subject_id,
    p.gender,
    -- Compute birth date: anchor_year - anchor_age
    DATE_SUB(p.anchor_year, INTERVAL p.anchor_age YEAR) AS birth_date,
    -- Age at admission
    DATE_DIFF(CAST(a.admittime AS DATE), DATE_SUB(p.anchor_year, INTERVAL p.anchor_age YEAR), YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
-- Filter admissions for age 59-69
admissions_filtered_age AS (
  SELECT *
  FROM admissions_with_age
  WHERE age_at_admission BETWEEN 59 AND 69
),
-- Admissions with DVT diagnosis in the admission
admissions_with_dvt AS (
  SELECT 
    a.*,
    d.icd_code AS dvt_icd_code
  FROM admissions_filtered_age a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
    AND d.icd_version = 10
    AND d.icd_code IN (SELECT icd_code FROM dvt_codes)
),
-- Join with patient_cci and patients for dod
cohort_base AS (
  SELECT 
    a.*,
    cci.cci,
    p.dod  -- for mortality
  FROM admissions_with_dvt a
  LEFT JOIN patient_cci cci
    ON a.subject_id = cci.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),
-- Compute 30-day mortality, ICU stay, death_days
cohort_with_metrics AS (
  SELECT 
    *,
    -- 30-day mortality
    CASE 
      WHEN dod IS NOT NULL AND dod <= DATE_ADD(CAST(admittime AS DATE), INTERVAL 30 DAY) 
      THEN 1 
      ELSE 0 
    END AS death_within_30_days,
    -- ICU stay
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
        WHERE i.hadm_id = cohort_base.hadm_id
      ) THEN 1 
      ELSE 0 
    END AS icu_stay,
    -- Death days
    CASE 
      WHEN dod IS NOT NULL AND dod >= CAST(admittime AS DATE) 
      THEN DATE_DIFF(dod, CAST(admittime AS DATE), DAY)
      ELSE NULL 
    END AS death_days
  FROM cohort_base
),
-- Compute 75th percentile of CCI
cci_percentile AS (
  SELECT 
    APPROX_QUANTILES(cci, 100) [OFFSET(75)] AS p75_cci
  FROM cohort_with_metrics
  WHERE cci IS NOT NULL
),
-- Filter for CCI above 75th percentile
cohort_filtered AS (
  SELECT 
    *,
    cci AS cci_score  -- alias for clarity
  FROM cohort_with_metrics
  WHERE cci >= (SELECT p75_cci FROM cci_percentile)
    AND cci IS NOT NULL
),
-- Final aggregation
final_cohort AS (
  SELECT 
    COUNT(*) AS cohort_size,
    AVG(death_within_30_days) AS thirty_day_mortality,
    AVG(icu_stay) AS major_complication_rate,
    (SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY death_days) 
     FROM cohort_filtered 
     WHERE death_days IS NOT NULL) AS median_survival_days,
    APPROX_QUANTILES(cci_score, 4) AS cci_quartiles
  FROM cohort_filtered
)
SELECT * FROM final_cohort;