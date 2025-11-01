WITH 
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 47 AND 57
),
acute_pancreatitis_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code IN ('K85.0', 'K85.1', 'K85.2', 'K85.3', 'K85.8', 'K85.9')  
  AND icd_version = 10  
),
admission_details AS (
  SELECT 
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    COUNT(DISTINCT CASE WHEN h.short_description LIKE '%CT%' OR h.short_description LIKE '%MRI%' THEN h.hcpcs_cd END) AS ct_mri_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_patients p ON a.subject_id = p.subject_id
  JOIN acute_pancreatitis_admissions apa ON a.hadm_id = apa.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h ON a.hadm_id = h.hadm_id
  GROUP BY a.hadm_id, a.admittime, a.dischtime
)
SELECT 
  CASE 
    WHEN los BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los BETWEEN 5 AND 8 THEN '5-8 days'
    ELSE 'Other'
  END AS los_category,
  COUNT(hadm_id) AS patient_count,
  AVG(ct_mri_count) AS mean_ct_mri_procedures
FROM admission_details
WHERE los BETWEEN 1 AND 8
GROUP BY los_category
ORDER BY los_category;