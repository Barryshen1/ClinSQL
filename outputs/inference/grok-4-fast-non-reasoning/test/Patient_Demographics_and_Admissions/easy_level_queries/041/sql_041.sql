WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 50 AND 60
),
first_icu_stays AS (
  SELECT 
    icu.subject_id,
    icu.stay_id,
    icu.hadm_id,
    icu.los
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN filtered_patients fp ON icu.subject_id = fp.subject_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) = 1
),
anticoagulant_cohort AS (
  SELECT DISTINCT
    fis.subject_id,
    fis.stay_id,
    fis.hadm_id,
    fis.los
  FROM first_icu_stays fis
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    ON p.subject_id = fis.subject_id 
    AND p.hadm_id = fis.hadm_id
  WHERE LOWER(p.drug) LIKE '%heparin%'
     OR LOWER(p.drug) LIKE '%warfarin%'
     OR LOWER(p.drug) LIKE '%enoxaparin%'
     OR LOWER(p.drug) LIKE '%rivaroxaban%'
     OR LOWER(p.drug) LIKE '%apixaban%'
     OR LOWER(p.drug) LIKE '%dabigatran%'
)
SELECT
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los_days
FROM anticoagulant_cohort;