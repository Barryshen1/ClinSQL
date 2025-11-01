WITH 
  -- Identify heart failure ICD codes (example codes, might need adjustment)
  hf_icd_codes AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE long_title LIKE '%Heart failure%'
  ),
  
  -- Identify CT/MRI ICD procedure codes (example codes, might need adjustment)
  ct_mri_icd_codes AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE long_title LIKE '%CT%' OR long_title LIKE '%MRI%'
  ),
  
  -- Admissions of interest
  admissions_of_interest AS (
    SELECT a.hadm_id, a.subject_id, p.anchor_age, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE p.gender = 'F' AND p.anchor_age BETWEEN 45 AND 55
    AND a.hospital_expire_flag = 0  -- Assuming alive at discharge
  ),
  
  -- LOS categorization
  los_categorization AS (
    SELECT hadm_id, 
           CASE 
             WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
             WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
             ELSE 'Out of range'
           END AS los_category
    FROM admissions_of_interest
  ),
  
  -- Diagnosis categorization (primary vs. secondary)
  diagnosis_categorization AS (
    SELECT hadm_id, 
           CASE 
             WHEN seq_num = 1 THEN 'Primary'
             ELSE 'Secondary'
           END AS diagnosis_category
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE hadm_id IN (SELECT hadm_id FROM admissions_of_interest)
    AND icd_code IN (SELECT icd_code FROM hf_icd_codes)
  ),
  
  -- Counting CT/MRI procedures
  ct_mri_counts AS (
    SELECT hadm_id, COUNT(*) as ct_mri_count
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    WHERE hadm_id IN (SELECT hadm_id FROM admissions_of_interest)
    AND icd_code IN (SELECT icd_code FROM ct_mri_icd_codes)
    GROUP BY hadm_id
  )

-- Final aggregation
SELECT 
  dc.diagnosis_category,
  lc.los_category,
  AVG(ctm.ct_mri_count) AS mean_ct_mri,
  MIN(ctm.ct_mri_count) AS min_ct_mri,
  MAX(ctm.ct_mri_count) AS max_ct_mri
FROM 
  diagnosis_categorization dc
  JOIN los_categorization lc ON dc.hadm_id = lc.hadm_id
  LEFT JOIN ct_mri_counts ctm ON lc.hadm_id = ctm.hadm_id
GROUP BY 
  dc.diagnosis_category, lc.los_category;