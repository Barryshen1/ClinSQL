WITH 
  -- Identify acute pancreatitis admissions
  pancreatitis_admissions AS (
    SELECT DISTINCT a.hadm_id, a.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    WHERE d.icd_code IN ('577.0', 'K85.0')  -- ICD-9 and ICD-10 codes for acute pancreatitis
  ),

  -- Filter for women aged 47-57
  target_patients AS (
    SELECT p.subject_id, p.gender, p.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE p.gender = 'F' AND p.anchor_age BETWEEN 47 AND 57
  ),

  -- Match patients with acute pancreatitis and target demographics
  eligible_patients AS (
    SELECT pa.hadm_id, pa.subject_id
    FROM pancreatitis_admissions pa
    JOIN target_patients tp ON pa.subject_id = tp.subject_id
  ),

  -- Calculate LOS and categorize
  los_categories AS (
    SELECT ea.hadm_id, 
           TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM eligible_patients ea
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON ea.hadm_id = a.hadm_id
  ),

  -- Identify CT/MRI procedures
  ct_mri_procedures AS (
    SELECT p.hadm_id, COUNT(*) AS ct_mri_count
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp ON p.icd_code = dp.icd_code
    WHERE dp.long_title LIKE '%CT%' OR dp.long_title LIKE '%MRI%'
    GROUP BY p.hadm_id
  )

-- Final calculation
SELECT 
  CASE 
    WHEN los.los BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los.los BETWEEN 5 AND 8 THEN '5-8 days'
  END AS los_category,
  COUNT(DISTINCT los.hadm_id) AS patient_count,
  COALESCE(AVG(ctmp.ct_mri_count), 0) AS mean_ct_mri_procedures
FROM los_categories los
LEFT JOIN ct_mri_procedures ctmp ON los.hadm_id = ctmp.hadm_id
GROUP BY 
  CASE 
    WHEN los.los BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los.los BETWEEN 5 AND 8 THEN '5-8 days'
  END
ORDER BY los_category;