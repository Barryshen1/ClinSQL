WITH population AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 48 AND 58
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        (icd_version = 10 AND icd_code LIKE 'E11%') OR
        (icd_version = 9 AND icd_code LIKE '250__' AND 
         SUBSTR(icd_code, 5, 1) IN ('0', '2'))
    )
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        (icd_version = 10 AND icd_code LIKE 'I50%') OR
        (icd_version = 9 AND icd_code LIKE '428%')
    )
),

glp1_admins AS (
  SELECT 
    e.hadm_id,
    MIN(e.charttime) AS first_glp1_time
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  WHERE 
    (LOWER(e.medication) LIKE '%liraglutide%' OR
     LOWER(e.medication) LIKE '%dulaglutide%' OR
     LOWER(e.medication) LIKE '%exenatide%' OR
     (LOWER(e.medication) LIKE '%semaglutide%' AND 
      LOWER(e.medication) NOT LIKE '%rybelsus%'))
  GROUP BY e.hadm_id
),

results AS (
  SELECT 
    p.hadm_id,
    -- Check first 72h window (clamped to admission duration)
    CASE WHEN g.first_glp1_time BETWEEN p.admittime 
         AND LEAST(TIMESTAMP_ADD(p.admittime, INTERVAL 72 HOUR), p.dischtime)
         THEN 1 ELSE 0 END AS in_first_72h,
    -- Check last 48h window (clamped to admission duration)
    CASE WHEN g.first_glp1_time BETWEEN GREATEST(TIMESTAMP_SUB(p.dischtime, INTERVAL 48 HOUR), p.admittime) 
         AND p.dischtime
         THEN 1 ELSE 0 END AS in_last_48h
  FROM population p
  LEFT JOIN glp1_admins g ON p.hadm_id = g.hadm_id
)

SELECT 
  COUNT(*) AS total_patients,
  SUM(in_first_72h) AS count_first_72h,
  ROUND(100.0 * SUM(in_first_72h) / COUNT(*), 2) AS rate_first_72h_pct,
  SUM(in_last_48h) AS count_last_48h,
  ROUND(100.0 * SUM(in_last_48h) / COUNT(*), 2) AS rate_last_48h_pct,
  ROUND(100.0 * SUM(in_first_72h) / COUNT(*) - 100.0 * SUM(in_last_48h) / COUNT(*), 2) AS absolute_difference_pct
FROM results;