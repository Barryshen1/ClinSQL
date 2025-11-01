WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 84 AND 94
),
echo_procs AS (
  SELECT 
    c.hadm_id,
    pi.icd_code
  FROM 
    cohort c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  ON 
    c.subject_id = pi.subject_id AND c.hadm_id = pi.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON 
    pi.icd_code = d.icd_code AND pi.icd_version = d.icd_version
  WHERE 
    LOWER(d.long_title) LIKE '%echocardiography%' 
    OR LOWER(d.long_title) LIKE '%echocardiogram%'
)
SELECT 
  MAX(cnt) AS max_distinct_echo_procs
FROM (
  SELECT 
    hadm_id,
    COUNT(DISTINCT icd_code) AS cnt
  FROM 
    echo_procs
  GROUP BY 
    hadm_id
);