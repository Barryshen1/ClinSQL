WITH target_procedures AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    REGEXP_CONTAINS(long_title, r'(?i)(pacemaker|defibrillator)') 
    AND REGEXP_CONTAINS(long_title, r'(?i)(insertion|implantation)')
),
hospitalizations_with_procedures AS (
  SELECT 
    p.hadm_id,
    COUNT(DISTINCT p.icd_code) AS num_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON a.subject_id = pt.subject_id
  INNER JOIN target_procedures tp
    ON p.icd_code = tp.icd_code AND p.icd_version = tp.icd_version
  WHERE 
    pt.gender = 'M'
    AND pt.anchor_age BETWEEN 82 AND 92
  GROUP BY p.hadm_id
)
SELECT 
  MIN(num_procedures) AS min_procedures_per_hospitalization
FROM hospitalizations_with_procedures;