WITH qualifying_hospitalizations AS (
  SELECT 
    p.hadm_id, 
    COUNT(DISTINCT p.icd_code) AS num_distinct_procs
  FROM 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code 
    AND p.icd_version = d.icd_version
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.hadm_id = a.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON a.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 57 AND 67
    AND LOWER(d.long_title) LIKE '%valve%'
    AND (LOWER(d.long_title) LIKE '%repair%' OR LOWER(d.long_title) LIKE '%replacement%')
  GROUP BY 
    p.hadm_id
  HAVING 
    num_distinct_procs > 0
)
SELECT 
  MIN(num_distinct_procs) AS minimum_distinct_valve_procedures_per_hospitalization
FROM 
  qualifying_hospitalizations;