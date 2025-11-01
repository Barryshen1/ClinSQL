SELECT 
  PERCENTILE_CONT(num_echocardiography_procedures, 0.25) WITHIN GROUP (ORDER BY num_echocardiography_procedures) AS percentile_25th
FROM (
  SELECT 
    pe.hadm_id,
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
    LOWER(di.label) LIKE '%echocardiography%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
  GROUP BY 
    pe.hadm_id
) AS counts;