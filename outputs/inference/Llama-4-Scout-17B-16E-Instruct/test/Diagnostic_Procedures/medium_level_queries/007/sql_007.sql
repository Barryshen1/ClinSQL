WITH 
  -- Identify female patients aged 50-60
  target_patients AS (
    SELECT subject_id
    FROM physionet-data.mimiciv_3_1_hosp.patients
    WHERE gender = 'F' AND anchor_age BETWEEN 50 AND 60
  ),
  
  -- Identify admissions with ACS
  acs_admissions AS (
    SELECT a.hadm_id, a.subject_id
    FROM physionet-data.mimiciv_3_1_hosp.admissions a
    JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
    WHERE d.icd_code LIKE '410%'  
    AND a.subject_id IN (SELECT subject_id FROM target_patients)
  ),
  
  -- Calculate LOS categories and identify primary/secondary diagnosis
  admission_details AS (
    SELECT 
      a.hadm_id,
      CASE 
        WHEN d.seq_num = 1 THEN 'Primary'
        ELSE 'Secondary'
      END as diagnosis_type,
      CASE 
        WHEN i.los BETWEEN 1 AND 4 THEN '1-4'
        WHEN i.los BETWEEN 5 AND 8 THEN '5-8'
        ELSE 'Outside range'
      END as los_category
    FROM acs_admissions a
    JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
    JOIN physionet-data.mimiciv_3_1_icu.icustays i ON a.hadm_id = i.hadm_id
  ),
  
  -- Identify diagnostic procedures per admission
  diagnostic_procedures AS (
    SELECT p.hadm_id, COUNT(p.icd_code) as num_procedures
    FROM physionet-data.mimiciv_3_1_hosp.procedures_icd p
    JOIN acs_admissions a ON p.hadm_id = a.hadm_id
    GROUP BY p.hadm_id
  )

-- Combine and calculate percentiles
SELECT 
  ad.diagnosis_type,
  ad.los_category,
  APPROX_QUANTILES(dp.num_procedures, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(dp.num_procedures, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(dp.num_procedures, 100)[OFFSET(75)] AS p75
FROM admission_details ad
JOIN diagnostic_procedures dp ON ad.hadm_id = dp.hadm_id
GROUP BY ad.diagnosis_type, ad.los_category;