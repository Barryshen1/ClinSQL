WITH
-- Get first admission per patient
first_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY hadm_id) AS admission_rank
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- Get first ICU stay per admission
first_icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    TIMESTAMP_DIFF(i.outtime, i.intime, DAY) AS los_days,
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS icu_rank
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN first_admissions fa ON i.subject_id = fa.subject_id AND i.hadm_id = fa.hadm_id
  WHERE fa.admission_rank = 1  -- First admission
),

-- Patients on anticoagulants during admission
anticoagulant_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN first_admissions fa ON p.subject_id = fa.subject_id AND p.hadm_id = fa.hadm_id
  WHERE fa.admission_rank = 1  -- First admission
  AND (
    -- Common anticoagulant drugs (expand as needed)
    LOWER(p.drug) LIKE '%warfarin%'
    OR LOWER(p.drug) LIKE '%heparin%'
    OR LOWER(p.drug) LIKE '%apixaban%'
    OR LOWER(p.drug) LIKE '%rivaroxaban%'
    OR LOWER(p.drug) LIKE '%dabigatran%'
    OR LOWER(p.drug) LIKE '%edoxaban%'
  )
),

-- Final cohort: females 50-60 on anticoagulants with first ICU stay
cohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    fis.los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN first_icu_stays fis ON p.subject_id = fis.subject_id
  JOIN anticoagulant_patients ap ON p.subject_id = ap.subject_id AND fis.hadm_id = ap.hadm_id
  WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 50 AND 60
  AND fis.icu_rank = 1  -- First ICU stay
)

-- Calculate median ICU LOS
SELECT
  PERCENTILE_CONT(cohort.los_days, 0.5) OVER() AS median_icu_los_days
FROM cohort
LIMIT 1;