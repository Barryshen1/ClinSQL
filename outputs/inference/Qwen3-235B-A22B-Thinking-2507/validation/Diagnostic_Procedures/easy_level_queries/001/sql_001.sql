WITH cardiac_procedures AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%cardiac%'
     OR LOWER(long_title) LIKE '%heart%'
     OR LOWER(long_title) LIKE '%coronary%'
     OR LOWER(long_title) LIKE '%valve%'
     OR LOWER(long_title) LIKE '%aorta%'
     OR LOWER(long_title) LIKE '%aortic%'
     OR LOWER(long_title) LIKE '%myocardial%'
),
admissions_filtered AS (
  SELECT 
    a.hadm_id,
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 63 AND 73
),
procedure_counts AS (
  SELECT 
    af.hadm_id,
    COUNT(DISTINCT CASE WHEN cp.icd_code IS NOT NULL THEN pic.icd_code END) AS count_procedures
  FROM admissions_filtered af
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pic
    ON af.hadm_id = pic.hadm_id
  LEFT JOIN cardiac_procedures cp
    ON pic.icd_code = cp.icd_code AND pic.icd_version = cp.icd_version
  GROUP BY af.hadm_id
)
SELECT 
  APPROX_QUANTILES(count_procedures, 1000)[OFFSET(750)] AS percentile_75
FROM procedure_counts;