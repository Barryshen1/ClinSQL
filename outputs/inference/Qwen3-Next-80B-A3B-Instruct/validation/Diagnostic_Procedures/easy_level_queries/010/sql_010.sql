WITH echocardiography_procedures AS (
  SELECT 
    p.subject_id,
    COUNT(*) AS num_echocardiography_procedures
  FROM 
    physionet-data.mimiciv_3_1_icu.procedureevents pe
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items di
    ON pe.itemid = di.itemid
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p
    ON pe.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 84 AND 94
    AND LOWER(di.label) LIKE '%echocardi%'
  GROUP BY 
    p.subject_id
)
SELECT 
  MAX(num_echocardiography_procedures) AS max_echocardiography_procedures_per_patient
FROM 
  echocardiography_procedures;