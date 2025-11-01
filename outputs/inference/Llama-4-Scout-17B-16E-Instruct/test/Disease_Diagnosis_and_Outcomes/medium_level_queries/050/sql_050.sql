WITH 
  -- Identify patients of interest
  patients_of_interest AS (
    SELECT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    WHERE p.gender = 'M' AND p.anchor_age BETWEEN 75 AND 85
  ),
  
  -- Identify sepsis and septic shock
  sepsis AS (
    SELECT subject_id, hadm_id, 
           CASE 
             WHEN icd_code IN ('99591', '99592', '785.52', '038.0', '038.1', '038.2', '038.3', '038.4', '038.40', '038.41', '038.42', '038.43', '038.44', '038.49', '999.3') THEN 'Sepsis'
             WHEN icd_code IN ('785.53', '038.8', '038.9') THEN 'Septic Shock'
             ELSE NULL
           END AS sepsis_status
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  ),
  
  -- Identify comorbidities
  comorbidities AS (
    SELECT subject_id, hadm_id,
           MAX(CASE WHEN icd_code IN ('585', '585.1', '585.2', '585.3', '585.4', '585.5', '585.6', '585.7', '585.8', '585.9', 'K92.0') THEN 1 ELSE 0 END) AS ckd,
           MAX(CASE WHEN icd_code IN ('250', '250.0', '250.1', '250.2', '250.3', '250.4', '250.5', '250.6', '250.7', '250.8', '250.9', 'E10', 'E11', 'E13') THEN 1 ELSE 0 END) AS diabetes,
           MAX(CASE WHEN icd_code IN ('427.31') THEN 1 ELSE 0 END) AS afib,
           MAX(CASE WHEN icd_code IN ('401', '401.0', '401.1', '401.2', '401.3', '401.4', '401.5', '401.6', '401.7', '401.8', '401.9', 'I10') THEN 1 ELSE 0 END) AS hypertension
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY subject_id, hadm_id
  ),
  
  -- Calculate LOS
  icu_stays AS (
    SELECT subject_id, hadm_id, stay_id, 
           DATE_DIFF(TIMESTAMP(icustays.outtime), TIMESTAMP(icustays.intime), DAY) AS los
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  )

SELECT 
  -- Stratification variables
  CASE WHEN i.los <= 5 THEN '≤5' ELSE '>5' END AS los_category,
  c.ckd, c.diabetes, c.afib, c.hypertension,
  -- Mortality
  SUM(CASE WHEN poi.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  COUNT(DISTINCT poi.hadm_id) AS total_patients
FROM patients_of_interest poi
JOIN sepsis s ON poi.subject_id = s.subject_id AND poi.hadm_id = s.hadm_id
JOIN comorbidities c ON poi.subject_id = c.subject_id AND poi.hadm_id = c.hadm_id
JOIN icu_stays i ON poi.subject_id = i.subject_id AND poi.hadm_id = i.hadm_id
WHERE s.sepsis_status = 'Sepsis'
  AND c.ckd IS NOT NULL AND c.diabetes IS NOT NULL AND c.afib IS NOT NULL AND c.hypertension IS NOT NULL
GROUP BY 
  CASE WHEN i.los <= 5 THEN '≤5' ELSE '>5' END,
  c.ckd, c.diabetes, c.afib, c.hypertension
;