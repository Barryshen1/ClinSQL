WITH admissions_with_age AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),
echocardiography_codes AS (
  SELECT 
    icd_code, 
    icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%echo%'
     OR LOWER(long_title) LIKE '%echocardiography%'
),
patients_in_group AS (
  SELECT DISTINCT subject_id
  FROM admissions_with_age
  WHERE gender = 'F'
    AND age_at_admission BETWEEN 81 AND 91
),
patient_procedures AS (
  SELECT 
    a.subject_id,
    p.icd_code,
    p.icd_version
  FROM admissions_with_age a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON a.hadm_id = p.hadm_id
  INNER JOIN echocardiography_codes ec
    ON p.icd_code = ec.icd_code 
    AND p.icd_version = ec.icd_version
  WHERE a.gender = 'F'
    AND a.age_at_admission BETWEEN 81 AND 91
),
patient_counts AS (
  SELECT 
    pig.subject_id,
    COUNT(DISTINCT CONCAT(p.icd_code, '_', CAST(p.icd_version AS STRING))) AS num_distinct_echo
  FROM patients_in_group pig
  LEFT JOIN patient_procedures p
    ON pig.subject_id = p.subject_id
  GROUP BY pig.subject_id
)
SELECT COALESCE(MAX(num_distinct_echo), 0) AS max_distinct_echo
FROM patient_counts;