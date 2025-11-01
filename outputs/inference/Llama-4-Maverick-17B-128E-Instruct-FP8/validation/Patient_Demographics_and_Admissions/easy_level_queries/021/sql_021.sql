WITH pneumonia_patients AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
  ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE diag.long_title LIKE '%Pneumonia%'
),
first_admission AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, 
         ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS admission_rank,
         a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 83 AND 93
  AND a.hadm_id IN (SELECT hadm_id FROM pneumonia_patients)
)
SELECT 
  COUNT(CASE WHEN hospital_expire_flag = 1 THEN 1 END) AS deaths,
  COUNT(*) AS total_patients,
  COUNT(CASE WHEN hospital_expire_flag = 1 THEN 1 END) * 100.0 / COUNT(*) AS mortality_rate
FROM first_admission
WHERE admission_rank = 1;