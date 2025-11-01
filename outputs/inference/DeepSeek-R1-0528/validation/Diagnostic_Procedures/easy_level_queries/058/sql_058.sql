WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND (
      p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
    ) BETWEEN 86 AND 96
),
mcs_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    LOWER(long_title) LIKE '%mechanical circulatory support%' OR
    LOWER(long_title) LIKE '%ecmo%' OR
    LOWER(long_title) LIKE '%intra-aortic balloon%' OR
    LOWER(long_title) LIKE '%ventricular assist%' OR
    LOWER(long_title) LIKE '%heart pump%'
),
procedure_counts AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT CONCAT(p.icd_code, '-', CAST(p.icd_version AS STRING))) AS distinct_procedures
  FROM cohort c
  LEFT JOIN (
    SELECT p.hadm_id, p.icd_code, p.icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    INNER JOIN mcs_codes m 
      ON p.icd_code = m.icd_code 
      AND p.icd_version = m.icd_version
  ) p
    ON c.hadm_id = p.hadm_id
  GROUP BY c.hadm_id
)
SELECT 
  APPROX_QUANTILES(distinct_procedures, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(distinct_procedures, 100)[OFFSET(75)] AS q3,
  APPROX_QUANTILES(distinct_procedures, 100)[OFFSET(75)] - 
  APPROX_QUANTILES(distinct_procedures, 100)[OFFSET(25)] AS iqr
FROM procedure_counts;