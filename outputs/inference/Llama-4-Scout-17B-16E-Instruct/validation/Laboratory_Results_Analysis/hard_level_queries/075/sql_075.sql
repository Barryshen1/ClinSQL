WITH 
target_patients AS (
  SELECT DISTINCT a.hadm_id, p.subject_id
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 42 AND 52
),

dvt_patients AS (
  SELECT hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd
  WHERE icd_code LIKE '453%'
)

SELECT 
  COUNT(DISTINCT tp.hadm_id) AS num_patients,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS num_deaths
FROM target_patients tp
JOIN dvt_patients dvt ON tp.hadm_id = dvt.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON tp.hadm_id = a.hadm_id;