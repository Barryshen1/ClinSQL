WITH 
-- Filter patients based on age and gender
filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 66 AND 76
),

-- Identify AMI patients
ami_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE d_icd.long_title LIKE '%Acute myocardial infarction%' AND diag.icd_version = 10
),

-- Get admission details
admission_details AS (
  SELECT 
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    adm.admission_type,
    (DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN ami_patients ON adm.hadm_id = ami_patients.hadm_id
  JOIN filtered_patients ON adm.subject_id = filtered_patients.subject_id
),

-- Categorize LOS and admission type
categorized_data AS (
  SELECT 
    hospital_expire_flag,
    DATETIME_DIFF(deathtime, admittime, DAY) AS time_to_death,
    CASE 
      WHEN los BETWEEN 1 AND 3 THEN '1-3'
      WHEN los BETWEEN 4 AND 7 THEN '4-7'
      ELSE '>=8'
    END AS los_category,
    CASE 
      WHEN admission_type = 'EMERGENCY' THEN 'Emergent'
      ELSE 'Non-Emergent'
    END AS admission_category
  FROM admission_details
)

SELECT 
  los_category,
  admission_category,
  COUNT(*) AS total_patients,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS in_hospital_mortality,
  APPROX_QUANTILES(time_to_death, 100)[OFFSET(50)] AS median_time_to_death
FROM categorized_data
GROUP BY los_category, admission_category
ORDER BY los_category, admission_category;