WITH 
  -- Patient demographics and admissions
  patients_admissions AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      p.gender, 
      p.anchor_age, 
      a.admittime, 
      a.dischtime, 
      a.deathtime,
      CASE 
        WHEN a.deathtime IS NOT NULL THEN 1 
        ELSE 0 
      END AS hospital_death
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON 
      a.subject_id = p.subject_id
  ),
  
  -- Sepsis identification (improved)
  sepsis_patients AS (
    SELECT DISTINCT 
      subject_id, 
      hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      icd_code IN ('R65.1', 'R65.0', 'A41.89', 'A41.9', 'A41.0')  
  ),
  
  -- Septic shock exclusion
  septic_shock_patients AS (
    SELECT DISTINCT 
      subject_id, 
      hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      icd_code IN ('785.52')  -- Septic shock ICD code
  ),
  
  -- CKD and Diabetes (enhanced)
  ckd_diabetes AS (
    SELECT 
      subject_id, 
      hadm_id,
      CASE 
        WHEN icd_code IN ('585', '585.1', '585.2', '585.3', '585.4', '585.5', '585.6', '585.9', 'K92.0', 'N18', 'N18.1', 'N18.2', 'N18.3', 'N18.4', 'N18.5', 'N18.6', 'N18.7', 'N18.8', 'N18.9') THEN 'CKD'
        WHEN icd_code IN ('250', '250.0', '250.1', '250.2', '250.3', '250.4', '250.5', '250.6', '250.7', '250.8', '250.9', 'E10', 'E11', 'E12', 'E13', 'E14') THEN 'Diabetes'
        ELSE NULL
      END AS condition
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  ),
  
  -- ICU stays
  icu_stays AS (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id, 
      intime, 
      outtime, 
      los
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
  ),
  
  -- Grouping variables
  grouped_data AS (
    SELECT 
      pa.subject_id, 
      pa.hadm_id, 
      pa.anchor_age,
      pa.gender,
      sp.hadm_id AS sepsis_hadm_id,
      icu.los,
      CASE 
        WHEN icu.los <= 5 THEN 'LOS_<=5'
        ELSE 'LOS_>5'
      END AS los_group,
      CASE 
        WHEN icu.stay_id IS NOT NULL THEN 'ICU'
        ELSE 'Non-ICU'
      END AS icu_group,
      pa.hospital_death,
      hd.condition
    FROM 
      patients_admissions pa
    LEFT JOIN 
      sepsis_patients sp 
    ON 
      pa.hadm_id = sp.hadm_id
    LEFT JOIN 
      icu_stays icu 
    ON 
      pa.hadm_id = icu.hadm_id
    LEFT JOIN 
      ckd_diabetes hd 
    ON 
      pa.hadm_id = hd.hadm_id
  )

-- Final analysis
SELECT 
  gd.los_group, 
  gd.icu_group, 
  COUNT(DISTINCT gd.hadm_id) AS N,
  SUM(gd.hospital_death) / COUNT(DISTINCT gd.hadm_id) * 100 AS mortality_pct,
  SUM(CASE WHEN gd.condition = 'CKD' THEN 1 ELSE 0 END) / COUNT(DISTINCT gd.hadm_id) * 100 AS ckd_prevalence,
  SUM(CASE WHEN gd.condition = 'Diabetes' THEN 1 ELSE 0 END) / COUNT(DISTINCT gd.hadm_id) * 100 AS diabetes_prevalence
FROM 
  grouped_data gd
WHERE 
  gd.gender = 'F'
  AND gd.anchor_age BETWEEN 49 AND 59
  AND gd.sepsis_hadm_id IS NOT NULL  
  AND gd.hadm_id NOT IN (SELECT hadm_id FROM septic_shock_patients)
GROUP BY 
  gd.los_group, 
  gd.icu_group;