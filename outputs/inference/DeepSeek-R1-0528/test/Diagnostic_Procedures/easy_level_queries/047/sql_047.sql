WITH cohort AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
),
admissions_cohort AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN cohort c ON a.subject_id = c.subject_id
),
procedure_events AS (
  SELECT 
    p.hadm_id,
    d.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE 
    UPPER(d.long_title) LIKE '%CATHETER ABLATION%' 
    OR UPPER(d.long_title) LIKE '%CARDIOVERSION%'
),
per_admission_procedure_count AS (
  SELECT 
    a.hadm_id,
    COUNT(p.hadm_id) AS num_procedures
  FROM admissions_cohort a
  LEFT JOIN procedure_events p ON a.hadm_id = p.hadm_id
  GROUP BY a.hadm_id
)
SELECT 
  STDDEV(num_procedures) AS sd_procedures
FROM per_admission_procedure_count;