WITH cohort AS (
  -- Patients: female, age 50-60
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
),

first_adm AS (
  -- First admission for each patient in cohort
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN cohort c
    ON a.subject_id = c.subject_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) = 1
),

anticoagulated AS (
  -- Patients with anticoagulant prescription during first admission
  SELECT DISTINCT fa.subject_id, fa.hadm_id
  FROM first_adm fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    ON fa.hadm_id = rx.hadm_id
    AND fa.subject_id = rx.subject_id
  WHERE LOWER(rx.drug) LIKE '%warfarin%'
     OR LOWER(rx.drug) LIKE '%heparin%'
     OR LOWER(rx.drug) LIKE '%enoxaparin%'
     OR LOWER(rx.drug) LIKE '%anticoagulant%'
     OR LOWER(rx.drug) LIKE '%dabigatran%'
     OR LOWER(rx.drug) LIKE '%rivaroxaban%'
     OR LOWER(rx.drug) LIKE '%apixaban%'
     OR LOWER(rx.drug) LIKE '%edoxaban%'
     OR LOWER(rx.drug) LIKE '%fondaparinux%'
),

first_icu AS (
  -- First ICU stay for each anticoagulated patient in the first admission
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN anticoagulated ac
    ON i.hadm_id = ac.hadm_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) = 1
)

-- Calculate median ICU LOS
SELECT APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_icu_los_days
FROM first_icu;