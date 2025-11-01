WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 82 AND 92
),
cardiac_procedures AS (
  SELECT DISTINCT p.subject_id, p.hadm_id, p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN eligible_patients ep ON p.subject_id = ep.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON p.icd_code = d.icd_code 
    AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%heart%'
     OR LOWER(d.long_title) LIKE '%coronary%'
     OR LOWER(d.long_title) LIKE '%cardiac%'
     OR LOWER(d.long_title) LIKE '%aortic valve%'
     OR LOWER(d.long_title) LIKE '%mitral valve%'
     OR LOWER(d.long_title) LIKE '%pericardium%'
     OR LOWER(d.long_title) LIKE '%cardiopulmonary%'
)
SELECT
  PERCENTILE_CONT(proc_count, 0.25) OVER() AS p25_distinct_cardiac_procedures
FROM (
  SELECT hadm_id, COUNT(DISTINCT icd_code) AS proc_count
  FROM cardiac_procedures
  GROUP BY hadm_id
  
  UNION ALL
  
  -- Include admissions with 0 cardiac procedures
  SELECT a.hadm_id, 0 AS proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN eligible_patients ep ON a.subject_id = ep.subject_id
  WHERE a.hadm_id NOT IN (SELECT hadm_id FROM cardiac_procedures)
) sub
;