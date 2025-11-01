WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_age AS age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_age BETWEEN 52 AND 62
),
valve_procs AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    pi.icd_code
  FROM 
    cohort c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  ON 
    c.subject_id = pi.subject_id AND c.hadm_id = pi.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
  ON 
    pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE 
    pi.icd_version = '10'
    AND LOWER(dip.long_title) LIKE '%valve%'
),
proc_counts AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT icd_code) AS num_distinct_valve_procs
  FROM 
    valve_procs
  GROUP BY 
    hadm_id
),
all_hosp AS (
  SELECT 
    c.hadm_id,
    COALESCE(pc.num_distinct_valve_procs, 0) AS num_distinct_valve_procs
  FROM 
    cohort c
  LEFT JOIN 
    proc_counts pc
  ON 
    c.hadm_id = pc.hadm_id
)
SELECT 
  PERCENTILE_CONT(0.25) WITHIN FRAME (ORDER BY num_distinct_valve_procs) AS q1,
  PERCENTILE_CONT(0.75) WITHIN FRAME (ORDER BY num_distinct_valve_procs) AS q3,
  q3 - q1 AS iqr
FROM 
  all_hosp;