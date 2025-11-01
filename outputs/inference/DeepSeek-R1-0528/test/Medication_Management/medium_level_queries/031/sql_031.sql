WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    -- Calculate exact age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
filtered_cohort AS (
  SELECT *
  FROM cohort
  WHERE age_at_admission BETWEEN 53 AND 63
),
diabetes AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '250%') OR
    (icd_version = 10 AND icd_code LIKE 'E1%')
),
heart_failure AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '428%') OR
    (icd_version = 10 AND 
      (icd_code LIKE 'I50%' OR 
       icd_code IN ('I110', 'I130', 'I132')))
),
cohort_with_diag AS (
  SELECT fc.*
  FROM filtered_cohort fc  -- Fixed typo: 'filted_cohort' -> 'filtered_cohort'
  WHERE fc.hadm_id IN (SELECT hadm_id FROM diabetes)
    AND fc.hadm_id IN (SELECT hadm_id FROM heart_failure)
),
glp1_events AS (
  SELECT 
    e.hadm_id,
    e.charttime,
    c.admittime,
    c.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  INNER JOIN cohort_with_diag c
    ON e.hadm_id = c.hadm_id
  WHERE 
    -- Filter for GLP-1 RA administrations (injectable only)
    LOWER(e.medication) LIKE '%exenatide%' OR
    LOWER(e.medication) LIKE '%liraglutide%' OR
    LOWER(e.medication) LIKE '%dulaglutide%' OR
    LOWER(e.medication) LIKE '%lixisenatide%' OR
    LOWER(e.medication) LIKE '%albiglutide%' OR
    LOWER(e.medication) LIKE '%byetta%' OR
    LOWER(e.medication) LIKE '%bydureon%' OR
    LOWER(e.medication) LIKE '%victoza%' OR
    LOWER(e.medication) LIKE '%saxenda%' OR
    LOWER(e.medication) LIKE '%trulicity%' OR
    LOWER(e.medication) LIKE '%ozempic%' OR
    LOWER(e.medication) LIKE '%adlyxin%'
    -- Exclude oral formulations
    AND LOWER(e.medication) NOT LIKE '%oral%'
    -- Ensure medication was administered
    AND e.event_txt = 'Given'
),
per_admission AS (
  SELECT 
    c.hadm_id,
    -- Flag if GLP-1 RA given in first 24h (using TIMESTAMP_ADD)
    MAX(CASE 
        WHEN g.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR) 
        THEN 1 ELSE 0 
    END) AS in_first_24h,
    -- Flag if GLP-1 RA given in final 12h (using TIMESTAMP_SUB)
    MAX(CASE 
        WHEN g.charttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime 
        THEN 1 ELSE 0 
    END) AS in_final_12h
  FROM cohort_with_diag c
  LEFT JOIN glp1_events g
    ON c.hadm_id = g.hadm_id
  GROUP BY c.hadm_id
)
SELECT 
  COUNT(hadm_id) AS total_admissions,
  SUM(in_first_24h) AS count_first_24h,
  SUM(in_final_12h) AS count_final_12h,
  ROUND(SUM(in_first_24h) * 100.0 / COUNT(hadm_id), 2) AS pct_first_24h,
  ROUND(SUM(in_final_12h) * 100.0 / COUNT(hadm_id), 2) AS pct_final_12h
FROM per_admission;