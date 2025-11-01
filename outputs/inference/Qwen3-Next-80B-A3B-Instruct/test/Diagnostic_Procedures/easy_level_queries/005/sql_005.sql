WITH echocardiography_procedures AS (
  -- ICU procedureevents with d_items
  SELECT p.subject_id
  FROM `physionet-data`.mimiciv_3_1_icu.procedureevents p
  JOIN `physionet-data`.mimiciv_3_1_icu.d_items d ON p.itemid = d.itemid
  WHERE LOWER(d.label) LIKE '%echocardiography%'
  
  UNION ALL
  
  -- HOSP procedures_icd with d_icd_procedures
  SELECT p.subject_id
  FROM `physionet-data`.mimiciv_3_1_hosp.procedures_icd p
  JOIN `physionet-data`.mimiciv_3_1_hosp.d_icd_procedures d ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%echocardiography%'
),
patient_counts AS (
  SELECT 
    e.subject_id,
    COUNT(*) AS num_echocardiograms
  FROM echocardiography_procedures e
  JOIN `physionet-data`.mimiciv_3_1_hosp.patients pat ON e.subject_id = pat.subject_id
  WHERE pat.gender = 'M' 
    AND pat.anchor_age BETWEEN 57 AND 67
  GROUP BY e.subject_id
)
SELECT APPROX_QUANTILES(num_echocardiograms, 4)[OFFSET(3)] AS p75_echocardiograms
FROM patient_counts;