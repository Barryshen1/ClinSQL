WITH 
tia_diagnoses AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code LIKE '433%'  
  OR icd_code LIKE 'R41.89'  
),

ct_mri_procedures AS (
  SELECT subject_id, hadm_id, COUNT(*) as ct_mri_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE icd_code LIKE '87%'  
  GROUP BY subject_id, hadm_id
),

patient_data AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age, 
    a.hadm_id, 
    ic.stay_id,
    ic.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic ON a.hadm_id = ic.hadm_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 50 AND 60
)

SELECT 
  CASE 
    WHEN pd.los BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN pd.los BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE 'Outside range'
  END as los_group,
  COUNT(DISTINCT pd.hadm_id) as patient_count,
  AVG(IFNULL(ctmp.ct_mri_count, 0)) as mean_ct_mri_per_admission
FROM patient_data pd
LEFT JOIN tia_diagnoses td ON pd.subject_id = td.subject_id AND pd.hadm_id = td.hadm_id
LEFT JOIN ct_mri_procedures ctmp ON pd.hadm_id = ctmp.hadm_id
WHERE td.hadm_id IS NOT NULL  
GROUP BY 
  CASE 
    WHEN pd.los BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN pd.los BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE 'Outside range'
  END;