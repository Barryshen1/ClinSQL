WITH ages AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime,
    p.gender,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
),
diag AS (
  SELECT DISTINCT 
    di.subject_id, 
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN ages ag 
    ON di.subject_id = ag.subject_id 
    AND di.hadm_id = ag.hadm_id
  WHERE (
    (di.icd_version = 9 AND (di.icd_code LIKE '410%' OR di.icd_code LIKE '786.5%'))
    OR
    (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'R07.%'))
  )
),
cohort AS (
  SELECT 
    ag.subject_id,
    ag.hadm_id
  FROM ages ag
  INNER JOIN diag d 
    ON ag.subject_id = d.subject_id 
    AND ag.hadm_id = d.hadm_id
  WHERE ag.age BETWEEN 82 AND 92
),
first_trop AS (
  SELECT 
    l.subject_id, 
    l.hadm_id, 
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN cohort c 
    ON l.subject_id = c.subject_id 
    AND l.hadm_id = c.hadm_id
  WHERE l.itemid = 50910 
    AND l.valuenum IS NOT NULL
),
initial_trop AS (
  SELECT 
    subject_id, 
    hadm_id, 
    valuenum
  FROM first_trop
  WHERE rn = 1 
    AND valuenum > 0.01
)
SELECT 
  PERCENTILE_CONT(valuenum, 0.25) OVER() AS p25,
  PERCENTILE_CONT(valuenum, 0.50) OVER() AS p50,
  PERCENTILE_CONT(valuenum, 0.75) OVER() AS p75,
  MIN(valuenum) OVER() AS min_val,
  MAX(valuenum) OVER() AS max_val
FROM initial_trop;