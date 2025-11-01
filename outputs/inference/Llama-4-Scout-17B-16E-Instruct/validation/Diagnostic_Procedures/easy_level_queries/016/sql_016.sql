WITH 
  patients_of_interest AS (
    SELECT a.subject_id, a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    WHERE p.gender = 'F' AND p.anchor_age BETWEEN 75 AND 85
  ),
  ecg_telemetry_procedures AS (
    SELECT p.subject_id, p.hadm_id, COUNT(DISTINCT pe.itemid) as num_procedures
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    JOIN patients_of_interest p ON pe.subject_id = p.subject_id AND pe.hadm_id = p.hadm_id
    WHERE pe.itemid IN (220050, 220179)
    GROUP BY p.subject_id, p.hadm_id
  )
SELECT 
  APPROX_QUANTILES(num_procedures, 0.75) AS percentile_75
FROM ecg_telemetry_procedures;