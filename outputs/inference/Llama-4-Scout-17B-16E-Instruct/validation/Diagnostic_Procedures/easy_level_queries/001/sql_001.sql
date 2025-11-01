WITH 
  -- Identify cardiac procedures (for simplicity, let's consider a broad range of cardiac ICD procedure codes)
  cardiac_procedures AS (
    SELECT 
      p.subject_id,
      p.hadm_id,
      COUNT(DISTINCT pr.icd_code) AS distinct_cardiac_procedures
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr 
        ON a.hadm_id = pr.hadm_id
    WHERE 
      p.anchor_age BETWEEN 63 AND 73
      AND p.gender = 'M'
      -- Example filter for cardiac procedures (expand as needed)
      AND pr.icd_code LIKE '37%'  -- e.g., codes for cardiac procedures
    GROUP BY 
      p.subject_id, p.hadm_id
  )

SELECT 
  APPROX_QUANTILES(distinct_cardiac_procedures, 100)[OFFSET(75)] AS percentile_75
FROM 
  cardiac_procedures;