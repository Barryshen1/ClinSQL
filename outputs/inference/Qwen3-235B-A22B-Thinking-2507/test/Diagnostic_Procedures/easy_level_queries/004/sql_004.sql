WITH 
cabg_codes AS (
  SELECT 
    icd_code, 
    icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    LOWER(long_title) LIKE '%bypass%coronary%'
    OR LOWER(long_title) LIKE '%coronary%bypass%'
    OR LOWER(long_title) LIKE '%cabg%'
),
age_group_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 41 AND 51
),
patients_in_group AS (
  SELECT DISTINCT subject_id
  FROM age_group_admissions
),
cabg_procedures AS (
  SELECT 
    p.subject_id,
    p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN cabg_codes c
    ON p.icd_code = c.icd_code AND p.icd_version = c.icd_version
  INNER JOIN age_group_admissions a
    ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
),
patient_cabg_counts AS (
  SELECT 
    p.subject_id,
    COUNT(c.hadm_id) AS cabg_count
  FROM patients_in_group p
  LEFT JOIN cabg_procedures c
    ON p.subject_id = c.subject_id
  GROUP BY p.subject_id
)
SELECT 
  STDDEV_POP(cabg_count) AS std_dev_cabg
FROM patient_cabg_counts;