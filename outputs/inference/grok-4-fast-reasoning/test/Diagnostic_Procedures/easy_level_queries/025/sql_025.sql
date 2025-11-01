SELECT MIN(num_procs) AS minimum_distinct_mcs_procedures
FROM (
  SELECT 
    pe.subject_id, 
    COUNT(DISTINCT pe.itemid) AS num_procs
  FROM 
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON pe.itemid = di.itemid
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON pe.subject_id = i.subject_id 
    AND pe.hadm_id = i.hadm_id 
    AND pe.stay_id = i.stay_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.subject_id = a.subject_id 
    AND i.hadm_id = a.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 40 AND 50
    AND (
      LOWER(di.label) LIKE '%intra-aortic%'
      OR LOWER(di.label) LIKE '%balloon pump%'
      OR LOWER(di.label) LIKE '%ecmo%'
      OR LOWER(di.label) LIKE '%extracorporeal membrane%'
      OR LOWER(di.label) LIKE '%ventricular assist%'
      OR LOWER(di.label) LIKE '%vad%'
      OR LOWER(di.label) LIKE '%impella%'
      OR LOWER(di.label) LIKE '%tandem%'
      OR LOWER(di.label) LIKE '%abiomed%'
      OR LOWER(di.label) LIKE '%heartmate%'
      OR LOWER(di.label) LIKE '%novacor%'
    )
  GROUP BY 
    pe.subject_id
) t;