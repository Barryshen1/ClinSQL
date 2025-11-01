WITH 
filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 88 AND 98
),
tia_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Transient ischemic attack%' AND a.subject_id IN (SELECT subject_id FROM filtered_patients)
),
admission_details AS (
  SELECT a.hadm_id, 
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
         EXISTS(SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` icu WHERE icu.hadm_id = a.hadm_id) AS icu_use
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE a.hadm_id IN (SELECT hadm_id FROM tia_admissions)
),
ct_mri_counts AS (
  SELECT h.hadm_id, COUNT(*) AS num_studies
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  WHERE h.hcpcs_cd IN ('70450', '70460', '70470', '72148', '72149', '72158')  
  AND h.hadm_id IN (SELECT hadm_id FROM tia_admissions)
  GROUP BY h.hadm_id
)
SELECT 
  CASE 
    WHEN ad.los BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN ad.los BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE 'Outside range'
  END AS los_category,
  ad.icu_use,
  APPROX_QUANTILES(cm.num_studies, 100)[OFFSET(50)] AS median_studies,
  APPROX_QUANTILES(cm.num_studies, 100)[OFFSET(25)] AS q1_studies,
  APPROX_QUANTILES(cm.num_studies, 100)[OFFSET(75)] AS q3_studies
FROM admission_details ad
LEFT JOIN ct_mri_counts cm ON ad.hadm_id = cm.hadm_id
WHERE ad.los BETWEEN 1 AND 7
GROUP BY los_category, ad.icu_use
ORDER BY los_category, ad.icu_use;