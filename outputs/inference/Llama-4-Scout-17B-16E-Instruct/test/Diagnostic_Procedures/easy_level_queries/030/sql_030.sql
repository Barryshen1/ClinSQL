WITH 
  -- Filter patients by age and gender
  target_patients AS (
    SELECT subject_id
    FROM physionet-data.mimiciv_3_1_hosp.patients
    WHERE gender = 'F'
    AND anchor_age BETWEEN 84 AND 94
  ),
  
  -- Identify echocardiography procedures
  echocardiography_procedures AS (
    SELECT p.hadm_id, p.icd_code
    FROM physionet-data.mimiciv_3_1_hosp.procedures_icd p
    JOIN physionet-data.mimiciv_3_1_hosp.d_icd_procedures d ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    WHERE d.long_title LIKE '%Echocardiography%'
  ),
  
  -- Count distinct echocardiography procedures per hospitalization
  procedure_counts AS (
    SELECT a.hadm_id, COUNT(DISTINCT ep.icd_code) AS procedure_count
    FROM physionet-data.mimiciv_3_1_hosp.admissions a
    JOIN target_patients tp ON a.subject_id = tp.subject_id
    LEFT JOIN echocardiography_procedures ep ON a.hadm_id = ep.hadm_id
    GROUP BY a.hadm_id
  )

-- Calculate the 25th percentile of procedure counts
SELECT 
  APPROX_QUANTILES(procedure_count, 25)[OFFSET(0)] AS percentile_25
FROM procedure_counts;