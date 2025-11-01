WITH procedure_counts AS (
  SELECT 
    p.hadm_id,
    COUNT(*) AS num_procedures
  FROM 
    physionet-data.mimiciv_3_1_hosp.procedures_icd p
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients pt
    ON p.subject_id = pt.subject_id
  WHERE 
    pt.gender = 'M'
    AND pt.anchor_age BETWEEN 37 AND 47
    AND (
      LOWER(d.long_title) LIKE '%catheter ablation%'
      OR LOWER(d.long_title) LIKE '%cardioversion%'
    )
  GROUP BY 
    p.hadm_id
)
SELECT 
  STDDEV(num_procedures) AS sd_procedures
FROM 
  procedure_counts;