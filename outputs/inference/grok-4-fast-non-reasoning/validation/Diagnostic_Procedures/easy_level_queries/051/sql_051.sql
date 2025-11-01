WITH filtered_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
),
ecg_telemetry_procs AS (
  SELECT DISTINCT pr.subject_id, pr.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  INNER JOIN filtered_patients fp ON pr.subject_id = fp.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON pr.hadm_id = adm.hadm_id
  WHERE (pr.icd_version = '9' 
         AND (pr.icd_code LIKE '89.4%' OR pr.icd_code LIKE '89.6%'))
     OR (pr.icd_version = '10' 
         AND pr.icd_code LIKE '5A0B%' AND pr.icd_code LIKE '%Z')  -- Basic ICD-10 filter for cardiac monitoring (simplified)
),
patient_proc_counts AS (
  SELECT 
    subject_id,
    COUNT(DISTINCT icd_code) AS distinct_ecg_telemetry_procs
  FROM ecg_telemetry_procs
  GROUP BY subject_id
)
SELECT 
  PERCENTILE_CONT(0.75, distinct_ecg_telemetry_procs) OVER() AS p75th_percentile
FROM patient_proc_counts;