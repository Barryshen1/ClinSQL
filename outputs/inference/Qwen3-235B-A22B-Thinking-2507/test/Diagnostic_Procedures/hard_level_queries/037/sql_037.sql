WITH icu_stays AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.los,
    a.hospital_expire_flag,
    -- Calculate age at admission using MIMIC-IV anchor method
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 53 AND 63
),
sepsis_diagnoses AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
    AND icd_code IN (
      'A41.0', 'A41.01', 'A41.02', 'A41.1', 'A41.2', 'A41.3', 'A41.4', 'A41.5', 
      'A41.50', 'A41.51', 'A41.52', 'A41.53', 'A41.54', 'A41.59', 'A41.8', 'A41.81', 
      'A41.89', 'A41.9', 'R65.20', 'R65.21'
    )
),
sepsis_stays AS (
  SELECT s.*
  FROM icu_stays s
  INNER JOIN sepsis_diagnoses d
    ON s.hadm_id = d.hadm_id
),
procedure_counts AS (
  SELECT 
    s.stay_id,
    COUNT(p.itemid) AS procedure_count
  FROM sepsis_stays s
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON s.stay_id = p.stay_id
    AND p.starttime >= s.intime
    AND p.starttime < TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
  GROUP BY s.stay_id
),
control_stays AS (
  SELECT s.*
  FROM icu_stays s
  LEFT JOIN sepsis_diagnoses d
    ON s.hadm_id = d.hadm_id
  WHERE d.hadm_id IS NULL
)
SELECT 
  (SELECT APPROX_QUANTILES(procedure_count, 1001)[OFFSET(750)] 
   FROM procedure_counts) AS sepsis_procedure_75,
  (SELECT APPROX_QUANTILES(procedure_count, 1001)[OFFSET(900)] 
   FROM procedure_counts) AS sepsis_procedure_90,
  (SELECT AVG(los) FROM control_stays) AS control_avg_icu_los,
  (SELECT AVG(hospital_expire_flag) FROM control_stays) AS control_hospital_mortality;