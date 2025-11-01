WITH valve_procedures AS (
     SELECT 
       p.subject_id, 
       p.hadm_id, 
       p.icd_code,
       d.long_title
     FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
     INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
       ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
     WHERE 
       LOWER(d.long_title) LIKE '%valve%' 
       AND (LOWER(d.long_title) LIKE '%repair%' 
            OR LOWER(d.long_title) LIKE '%replacement%' 
            OR LOWER(d.long_title) LIKE '%valvuloplasty%'
            OR LOWER(d.long_title) LIKE '%valvotomy%'
            OR LOWER(d.long_title) LIKE '%valvulotomy%'
            OR LOWER(d.long_title) LIKE '%valvular%'
            OR LOWER(d.long_title) LIKE '%valvular%')
   );