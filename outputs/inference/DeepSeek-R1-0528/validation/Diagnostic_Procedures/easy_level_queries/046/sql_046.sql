WITH procedure_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    REGEXP_CONTAINS(LOWER(long_title), r'intra-aortic balloon|balloon pump|ecmo|extracorporeal membrane oxygenation|ventricular assist device|vad|heart assist system|mechanical circulatory support')
),
cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id,
    a.admittime,
    p.anchor_year,
    p.anchor_age,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS admission_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 80 AND 90
),
procedure_counts AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT 
      CASE WHEN pc.icd_code IS NOT NULL THEN p.icd_code ELSE NULL END
    ) AS num_procedures
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON c.hadm_id = p.hadm_id
  LEFT JOIN procedure_codes pc
    ON p.icd_code = pc.icd_code 
    AND p.icd_version = pc.icd_version
  GROUP BY c.hadm_id
)
SELECT MAX(num_procedures) AS max_distinct_procedures
FROM procedure_counts;