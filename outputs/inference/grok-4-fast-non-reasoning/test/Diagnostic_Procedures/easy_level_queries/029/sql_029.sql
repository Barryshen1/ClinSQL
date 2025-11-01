WITH patient_procedures AS (
  SELECT 
    p.subject_id,
    COUNT(DISTINCT pr.icd_code) AS distinct_proc_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON pr.icd_code = d.icd_code 
    AND pr.icd_version = d.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND pr.icd_code LIKE '0JH6%'
  GROUP BY 
    p.subject_id
)

SELECT 
  PERCENTILE_CONT(distinct_proc_count, 0.25) OVER (ORDER BY distinct_proc_count) AS p25_distinct_procedures
FROM 
  patient_procedures;