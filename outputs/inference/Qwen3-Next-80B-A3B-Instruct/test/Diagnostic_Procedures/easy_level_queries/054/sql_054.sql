WITH echocardiography_counts AS (
  SELECT 
    p.subject_id,
    COUNT(*) AS echocardiography_count
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON p.subject_id = pe.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items di
    ON pe.itemid = di.itemid
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND LOWER(di.label) LIKE '%echocardi%'
  GROUP BY 
    p.subject_id
)
SELECT 
  MAX(echocardiography_count) AS max_echocardiography_procedures_per_patient
FROM 
  echocardiography_counts;