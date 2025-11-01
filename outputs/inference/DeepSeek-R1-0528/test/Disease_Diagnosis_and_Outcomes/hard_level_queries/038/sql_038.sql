WITH 
-- Base cohort: Male inpatients aged 74-84
general_cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 74 AND 84
),

-- Identify AKI patients via ICD codes
aki_cohort AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '584%') 
    OR (icd_version = 10 AND icd_code LIKE 'N17%')
),

-- Identify ARDS patients via ICD codes
ards_diagnosis AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code = '51882') 
    OR (icd_version = 10 AND icd_code = 'J80')
),

-- Part 1: AKI Cohort 30-Day Mortality
aki_mortality AS (
  SELECT 
    COUNT(*) AS total_aki_patients,
    COUNTIF(DATE_DIFF(DATE(dod), DATE(admittime), DAY) <= 30) AS deceased_30d,
    COUNTIF(DATE_DIFF(DATE(dod), DATE(admittime), DAY) <= 30) / COUNT(*) AS mortality_30d_rate
  FROM general_cohort gc
  INNER JOIN aki_cohort ak ON gc.hadm_id = ak.hadm_id
),

-- Part 2: ARDS Rate and Survivor LOS for both cohorts
cohort_summary AS (
  SELECT 
    CASE 
      WHEN ak.hadm_id IS NOT NULL THEN 'AKI Cohort' 
      ELSE 'General Cohort' 
    END AS cohort_type,
    gc.hadm_id,
    -- ARDS flag
    IF(ad.hadm_id IS NOT NULL, 1, 0) AS ards_flag,
    -- LOS for survivors (in days)
    IF(gc.hospital_expire_flag = 0, 
       DATETIME_DIFF(gc.dischtime, gc.admittime, DAY), 
       NULL) AS los_days
  FROM general_cohort gc
  LEFT JOIN aki_cohort ak ON gc.hadm_id = ak.hadm_id
  LEFT JOIN ards_diagnosis ad ON gc.hadm_id = ad.hadm_id
),

-- Aggregate ARDS rate and LOS stats
cohort_aggregates AS (
  SELECT 
    cohort_type,
    COUNT(*) AS total_patients,
    -- ARDS rate
    COUNTIF(ards_flag = 1) / COUNT(*) AS ards_rate,
    -- Median and IQR for LOS (only survivors)
    APPROX_QUANTILES(los_days, 100 IGNORE NULLS)[OFFSET(50)] AS median_survivor_los,
    APPROX_QUANTILES(los_days, 100 IGNORE NULLS)[OFFSET(25)] AS q1_survivor_los,
    APPROX_QUANTILES(los_days, 100 IGNORE NULLS)[OFFSET(75)] AS q3_survivor_los
  FROM cohort_summary
  GROUP BY cohort_type
)

-- Final Output
SELECT 
  (SELECT mortality_30d_rate FROM aki_mortality) AS aki_30d_mortality_rate,
  cohort_type,
  ards_rate,
  median_survivor_los,
  q1_survivor_los,
  q3_survivor_los
FROM cohort_aggregates;