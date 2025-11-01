WITH target_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 57 AND 67
),
echocardiography_procedures AS (
  SELECT subject_id, COUNT(DISTINCT procedure_code) AS procedure_count
  FROM (
    -- HOSP procedures_icd
    SELECT p.subject_id, p.icd_code AS procedure_code
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
      ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    WHERE LOWER(d.long_title) LIKE '%echocardiography%'
    
    UNION ALL
    
    -- ICU procedureevents
    SELECT pe.subject_id, CAST(pe.itemid AS STRING) AS procedure_code
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
      ON pe.itemid = di.itemid
    WHERE LOWER(di.label) LIKE '%echocardiogram%'
    
    UNION ALL
    
    -- hcpcsevents
    SELECT h.subject_id, h.hcpcs_cd AS procedure_code
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh 
      ON h.hcpcs_cd = dh.code
    WHERE LOWER(dh.short_description) LIKE '%echocardiography%'
       OR LOWER(dh.short_description) LIKE '%echocardiogram%'
  ) AS combined
  GROUP BY subject_id
)
SELECT PERCENTILE_CONT(procedure_count, 0.75) OVER () AS percentile_75
FROM echocardiography_procedures
WHERE subject_id IN (SELECT subject_id FROM target_patients)
LIMIT 1;