WITH base AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
),

icd_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    REGEXP_CONTAINS(long_title, r'(?i)coronary') AND 
    (REGEXP_CONTAINS(long_title, r'(?i)angiography') OR 
     REGEXP_CONTAINS(long_title, r'(?i)angioplasty') OR 
     REGEXP_CONTAINS(long_title, r'(?i)stent'))
),

hcpcs_codes AS (
  SELECT code
  FROM `physionet-data.mimiciv_3_1_hosp.d_hcpcs`
  WHERE 
    REGEXP_CONTAINS(short_description, r'(?i)coronary') AND 
    (REGEXP_CONTAINS(short_description, r'(?i)angiography') OR 
     REGEXP_CONTAINS(short_description, r'(?i)angioplasty') OR 
     REGEXP_CONTAINS(short_description, r'(?i)stent'))
),

proc_icd AS (
  SELECT p.hadm_id, p.icd_code AS proc_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN icd_codes c
    ON p.icd_code = c.icd_code AND p.icd_version = c.icd_version
),

proc_hcpcs AS (
  SELECT h.hadm_id, h.hcpcs_cd AS proc_code
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN hcpcs_codes c
    ON h.hcpcs_cd = c.code
),

all_proc AS (
  SELECT hadm_id, proc_code FROM proc_icd
  UNION ALL
  SELECT hadm_id, proc_code FROM proc_hcpcs
),

distinct_proc_per_hadm AS (
  SELECT hadm_id, COUNT(DISTINCT proc_code) AS num_procedures
  FROM all_proc
  GROUP BY hadm_id
),

hadm_counts AS (
  SELECT 
    base.hadm_id, 
    COALESCE(distinct_proc_per_hadm.num_procedures, 0) AS num_procedures
  FROM base
  LEFT JOIN distinct_proc_per_hadm 
    ON base.hadm_id = distinct_proc_per_hadm.hadm_id
)

SELECT 
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS percentile_75
FROM hadm_counts;