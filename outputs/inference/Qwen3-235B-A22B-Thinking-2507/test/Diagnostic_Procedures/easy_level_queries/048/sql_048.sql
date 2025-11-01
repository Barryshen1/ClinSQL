WITH base_admissions AS (
  SELECT 
    adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 52 AND 62
),
valve_procedures AS (
  SELECT 
    proc.hadm_id,
    proc.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_proc
    ON proc.icd_code = d_proc.icd_code 
    AND proc.icd_version = d_proc.icd_version
  WHERE 
    (LOWER(d_proc.long_title) LIKE '%valve%' 
     AND (LOWER(d_proc.long_title) LIKE '%repair%' 
          OR LOWER(d_proc.long_title) LIKE '%replace%'))
    OR
    LOWER(d_proc.long_title) LIKE '%valvuloplasty%'
),
procedure_counts AS (
  SELECT 
    base.hadm_id,
    COUNT(DISTINCT vp.icd_code) AS count_procedures
  FROM base_admissions base
  LEFT JOIN valve_procedures vp
    ON base.hadm_id = vp.hadm_id
  GROUP BY base.hadm_id
)
SELECT 
  APPROX_QUANTILES(count_procedures, 1000)[OFFSET(750)] 
  - APPROX_QUANTILES(count_procedures, 1000)[OFFSET(250)] AS iqr
FROM procedure_counts;