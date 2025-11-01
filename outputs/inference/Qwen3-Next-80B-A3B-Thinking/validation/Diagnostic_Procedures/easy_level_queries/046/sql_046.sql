WITH eligible_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 80 AND 90
),
procedures AS (
  SELECT e.hadm_id, p.icd_code AS procedure_code
  FROM eligible_admissions e
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON e.hadm_id = p.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%ecmo%'
     OR LOWER(d.long_title) LIKE '%iabp%'
     OR LOWER(d.long_title) LIKE '%vad%'
     OR LOWER(d.long_title) LIKE '%ventricular assist device%'
     OR LOWER(d.long_title) LIKE '%balloon pump%'
     OR LOWER(d.long_title) LIKE '%mechanical circulatory support%'
     OR LOWER(d.long_title) LIKE '%extracorporeal membrane oxygenation%'
  
  UNION ALL
  
  SELECT e.hadm_id, CAST(p.itemid AS STRING) AS procedure_code
  FROM eligible_admissions e
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON e.hadm_id = p.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON p.itemid = d.itemid
  WHERE LOWER(d.label) LIKE '%ecmo%'
     OR LOWER(d.label) LIKE '%iabp%'
     OR LOWER(d.label) LIKE '%vad%'
     OR LOWER(d.label) LIKE '%ventricular assist device%'
     OR LOWER(d.label) LIKE '%balloon pump%'
     OR LOWER(d.label) LIKE '%mechanical circulatory support%'
     OR LOWER(d.label) LIKE '%extracorporeal membrane oxygenation%'
)
SELECT MAX(procedure_count) AS max_distinct_procedures
FROM (
  SELECT hadm_id, COUNT(DISTINCT procedure_code) AS procedure_count
  FROM procedures
  GROUP BY hadm_id
) counts;