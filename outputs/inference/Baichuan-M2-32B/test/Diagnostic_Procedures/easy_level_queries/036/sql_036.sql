WITH patient_birth AS (
  SELECT 
    subject_id, 
    anchor_year - anchor_age AS birth_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
),
admissions_with_age AS (
  SELECT 
    a.subject_id, 
    a.hadm_id,
    a.admittime,
    EXTRACT(YEAR FROM a.admittime) - p.birth_year AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patient_birth p ON a.subject_id = p.subject_id
  WHERE EXTRACT(YEAR FROM a.admittime) - p.birth_year BETWEEN 42 AND 52
),
valve_procedures AS (
  SELECT 
    awa.subject_id, 
    pr.icd_code
  FROM admissions_with_age awa
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON awa.subject_id = pr.subject_id
    AND awa.hadm_id = pr.hadm_id
  WHERE pr.icd_code IN ('35.0', '35.1', '35.2', '35.3', '35.4', '35.5', '35.6', '35.7', '35.8', '35.9')
),
distinct_procedures_per_patient AS (
  SELECT 
    subject_id, 
    COUNT(DISTINCT icd_code) AS num_distinct_valve_procedures
  FROM valve_procedures
  GROUP BY subject_id
)
SELECT 
  AVG(num_distinct_valve_procedures) AS avg_distinct_valve_procedures
FROM distinct_procedures_per_patient;