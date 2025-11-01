WITH 
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 72 AND 82
),
emergency_admissions AS (
  SELECT a.hadm_id, a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE a.admission_location = 'EMERGENCY ROOM ADMIT'
  AND a.subject_id IN (SELECT subject_id FROM eligible_patients)
),
pancreatitis_admissions AS (
  SELECT DISTINCT ea.hadm_id, ea.subject_id
  FROM emergency_admissions ea
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON ea.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE di.seq_num = 1 AND LOWER(dicd.long_title) LIKE '%acute pancreatitis%'
),
total_admissions AS (
  SELECT COUNT(a.hadm_id) AS total_admissions_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE a.subject_id IN (SELECT subject_id FROM pancreatitis_admissions)
)

SELECT total_admissions_count
FROM total_admissions;