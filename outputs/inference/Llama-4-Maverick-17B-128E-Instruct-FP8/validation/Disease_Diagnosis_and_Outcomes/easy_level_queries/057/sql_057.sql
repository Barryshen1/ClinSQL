WITH patient_selection AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 88 AND 98
),
pneumonia_admissions AS (
  SELECT DISTINCT ad.subject_id, ad.hadm_id, ad.admittime, ad.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` ad
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON ad.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE d_diag.long_title LIKE '%Pneumonia%'  -- Simplification; actual ICD codes should be reviewed
    AND ad.admission_type = 'EMERGENCY'  -- Likely community-acquired
),
los_calculation AS (
  SELECT subject_id, hadm_id, 
         DATETIME_DIFF(dischtime, admittime, DAY) AS los_days
  FROM pneumonia_admissions
)
SELECT MIN(los_days) AS min_los_days
FROM los_calculation
WHERE subject_id IN (SELECT subject_id FROM patient_selection);