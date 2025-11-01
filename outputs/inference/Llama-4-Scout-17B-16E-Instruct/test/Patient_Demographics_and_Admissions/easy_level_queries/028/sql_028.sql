WITH 
-- Identify patients of interest
patients_of_interest AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.anchor_age BETWEEN 90 AND 100
    AND p.gender = 'M'
),
-- Identify sepsis patients
sepsis_patients AS (
  SELECT DISTINCT a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE d.icd_code LIKE '995.92'  -- ICD-9 code for sepsis
     OR d.icd_code LIKE 'R65.1'   -- ICD-10 code for sepsis
),
-- Calculate ICU LOS for eligible patients
icu_los AS (
  SELECT 
    i.stay_id,
    DATE_DIFF(i.outtime, i.intime, DAY) AS icu_los_days
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN patients_of_interest p ON i.subject_id = p.subject_id
  JOIN sepsis_patients s ON i.subject_id = s.subject_id
  WHERE i.outtime IS NOT NULL AND i.intime IS NOT NULL
)
-- Calculate standard deviation of ICU LOS
SELECT 
  STDDEV(icu_los_days) AS stddev_icu_los_days
FROM icu_los;