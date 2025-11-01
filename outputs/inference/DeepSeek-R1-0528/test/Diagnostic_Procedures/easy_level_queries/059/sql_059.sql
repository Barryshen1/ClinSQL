WITH filtered_admissions AS (
  SELECT 
    a.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 76 AND 86
),
procedure_counts AS (
  SELECT 
    f.hadm_id,
    COUNT(DISTINCT CONCAT(pr.icd_code, '-', CAST(pr.icd_version AS STRING))) AS num_procedures
  FROM 
    filtered_admissions f
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr 
    ON f.hadm_id = pr.hadm_id
    AND (
      (pr.icd_version = 9 AND pr.icd_code LIKE '3[5-9]%')  -- ICD-9: 35-39
      OR 
      (pr.icd_version = 10 AND pr.icd_code LIKE '02%')     -- ICD-10: '02xxx...'
    )
  GROUP BY 
    f.hadm_id
)
SELECT 
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS q3,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] - APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS iqr
FROM 
  procedure_counts;