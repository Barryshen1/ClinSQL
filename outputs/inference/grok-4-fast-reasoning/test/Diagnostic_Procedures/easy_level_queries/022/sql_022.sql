WITH qualifying_procedures AS (
  SELECT 
    proc.hadm_id,
    COUNT(DISTINCT proc.icd_code) AS proc_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON proc.icd_code = d.icd_code 
    AND proc.icd_version = d.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND (
      LOWER(d.long_title) LIKE '%pacemaker%' 
      OR LOWER(d.long_title) LIKE '%defibrillator%'
    )
    AND (
      LOWER(d.long_title) LIKE '%implant%' 
      OR LOWER(d.long_title) LIKE '%insert%'
    )
  GROUP BY 
    proc.hadm_id
  HAVING 
    proc_count > 0
)
SELECT 
  MIN(proc_count) AS min_distinct_procedures
FROM 
  qualifying_procedures;