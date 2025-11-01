WITH female_40_50 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 40 AND 50
),
hosp_procedures AS (
  SELECT p.subject_id, p.icd_code AS procedure_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%ecmo%' 
     OR LOWER(d.long_title) LIKE '%iabp%' 
     OR LOWER(d.long_title) LIKE '%vad%' 
     OR LOWER(d.long_title) LIKE '%mechanical circulatory support%'
),
icu_procedures AS (
  SELECT pe.subject_id, CAST(pe.itemid AS STRING) AS procedure_code
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%ecmo%' 
     OR LOWER(di.label) LIKE '%iabp%' 
     OR LOWER(di.label) LIKE '%vad%' 
     OR LOWER(di.label) LIKE '%mechanical circulatory support%'
),
all_procedures AS (
  SELECT subject_id, procedure_code FROM hosp_procedures
  UNION ALL
  SELECT subject_id, procedure_code FROM icu_procedures
),
patient_counts AS (
  SELECT subject_id, COUNT(DISTINCT procedure_code) AS num_procedures
  FROM all_procedures
  WHERE subject_id IN (SELECT subject_id FROM female_40_50)
  GROUP BY subject_id
)
SELECT MIN(num_procedures) AS min_distinct_procedures
FROM patient_counts;