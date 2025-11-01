WITH 
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 57 AND 67
),
eligible_admissions AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_patients ep ON a.subject_id = ep.subject_id
),
sepsis_patients AS (
  SELECT DISTINCT di.hadm_id, 
         CASE 
           WHEN dicd.long_title LIKE '%septic shock%' THEN 'Septic Shock'
           ELSE 'Sepsis'
         END AS sepsis_status
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%sepsis%' OR dicd.long_title LIKE '%septic shock%'
),
charlson_index AS (
  SELECT hadm_id, 
         SUM(CASE 
               WHEN dicd.icd_code IN ('410.01', '410.11', '410.21', '410.31', '410.41', '410.51', '410.61', '410.71', '410.81', '410.91') THEN 1  
               WHEN dicd.icd_code LIKE '428%' THEN 1  
               WHEN dicd.icd_code LIKE '4%' AND dicd.icd_code NOT IN ('401.0', '401.1', '401.9') THEN 1  
               WHEN dicd.icd_code LIKE '430%' OR dicd.icd_code LIKE '431%' OR dicd.icd_code LIKE '432%' OR dicd.icd_code LIKE '433%' OR dicd.icd_code LIKE '434%' OR dicd.icd_code LIKE '435%' OR dicd.icd_code LIKE '436%' THEN 1  
               WHEN dicd.icd_code LIKE '440%' THEN 1  
               ELSE 0
             END) AS charlson_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  GROUP BY hadm_id
),
patient_outcomes AS (
  SELECT a.hadm_id, 
         ie.los,
         CASE WHEN a.deathtime IS NOT NULL THEN 1 ELSE 0 END AS in_hospital_mortality
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON a.hadm_id = ie.hadm_id
),
combined_data AS (
  SELECT sp.sepsis_status, 
         po.los,
         ci.charlson_score,
         po.in_hospital_mortality
  FROM sepsis_patients sp
  JOIN patient_outcomes po ON sp.hadm_id = po.hadm_id
  JOIN charlson_index ci ON sp.hadm_id = ci.hadm_id
  JOIN eligible_admissions ea ON sp.hadm_id = ea.hadm_id
)
SELECT 
  sepsis_status,
  CASE WHEN los <= 7 THEN 'LOS <= 7' ELSE 'LOS > 7' END AS los_category,
  CASE 
    WHEN charlson_score <= 3 THEN 'Charlson <= 3'
    WHEN charlson_score BETWEEN 4 AND 5 THEN 'Charlson 4-5'
    ELSE 'Charlson > 5'
  END AS charlson_category,
  COUNT(*) AS total_patients,
  SUM(in_hospital_mortality) AS total_deaths,
  (SUM(in_hospital_mortality) / COUNT(*)) * 100 AS mortality_percentage
FROM combined_data
GROUP BY sepsis_status, los_category, charlson_category
ORDER BY sepsis_status, los_category, charlson_category;