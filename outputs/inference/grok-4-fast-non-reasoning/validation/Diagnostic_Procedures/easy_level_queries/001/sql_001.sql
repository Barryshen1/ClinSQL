WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
),
cardiac_procedures_per_hadm AS (
  SELECT 
    pa.hadm_id,
    COUNT(DISTINCT proc.icd_code) AS num_distinct_cardiac_procs
  FROM 
    patient_admissions pa
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  ON 
    pa.hadm_id = proc.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
  ON 
    proc.icd_code = dproc.icd_code
    AND proc.icd_version = dproc.icd_version
  WHERE 
    (dproc.long_title LIKE '%heart%'
     OR dproc.long_title LIKE '%cardiac%'
     OR dproc.long_title LIKE '%coronary%'
     OR dproc.long_title LIKE '%aortic valve%'
     OR dproc.long_title LIKE '%mitral valve%'
     OR dproc.long_title LIKE '%cardiopulmonary%'
     OR dproc.long_title LIKE '%pericard%')
  GROUP BY 
    pa.hadm_id
  HAVING 
    num_distinct_cardiac_procs > 0  -- Optional: exclude admissions with no cardiac procs
)
SELECT 
  PERCENTILE_CONT(0.75) IGNORE NULLS OVER (ORDER BY num_distinct_cardiac_procs) AS p75_num_distinct_cardiac_procs
FROM 
  cardiac_procedures_per_hadm;