WITH target_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS admission_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
filtered_admissions AS (
  SELECT hadm_id
  FROM target_admissions
  WHERE admission_age BETWEEN 82 AND 92
),
cardiac_procedures AS (
  SELECT 
    hadm_id, 
    icd_code, 
    icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE 
    (icd_version = 9 AND SUBSTR(icd_code, 1, 2) BETWEEN '35' AND '39') 
    OR (icd_version = 10 AND SUBSTR(icd_code, 1, 2) = '02')
),
procedure_counts AS (
  SELECT 
    fa.hadm_id, 
    COUNT(DISTINCT CONCAT(cp.icd_code, '|', cp.icd_version)) AS cardiac_proc_count
  FROM filtered_admissions fa
  LEFT JOIN cardiac_procedures cp
    ON fa.hadm_id = cp.hadm_id
  GROUP BY fa.hadm_id
)
SELECT 
  APPROX_QUANTILES(cardiac_proc_count, 100)[OFFSET(25)] AS percentile_25th
FROM procedure_counts;