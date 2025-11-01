WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    a.dischtime IS NOT NULL
    AND p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 48 AND 58
),
diagnoses AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN icd_code LIKE 'E11%' AND icd_version = 10 THEN 1 ELSE 0 END) AS has_t2dm,
    MAX(CASE WHEN icd_code LIKE 'I50%' AND icd_version = 10 THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
admission_periods AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.admittime AS first72h_start,
    LEAST(c.admittime + INTERVAL 72 HOUR, c.dischtime) AS first72h_end,
    GREATEST(c.admittime, c.dischtime - INTERVAL 48 HOUR) AS last48h_start,
    c.dischtime AS last48h_end
  FROM cohort c
),
glp1_flags AS (
  SELECT 
    a.hadm_id,
    a.first72h_start,
    a.first72h_end,
    a.last48h_start,
    a.last48h_end,
    MAX(CASE 
          WHEN LOWER(p.drug) LIKE '%glp-1%' OR 
               LOWER(p.drug) LIKE '%semaglutide%' OR 
               LOWER(p.drug) LIKE '%liraglutide%' OR 
               LOWER(p.drug) LIKE '%dulaglutide%' OR 
               LOWER(p.drug) LIKE '%exenatide%' OR 
               LOWER(p.drug) LIKE '%tirzepatide%' 
          AND 
          (LOWER(p.route) LIKE '%subcut%' OR 
           LOWER(p.route) LIKE '%intramuscular%' OR 
           LOWER(p.route) LIKE '%intravenous%')
          AND p.starttime BETWEEN a.first72h_start AND a.first72h_end
          THEN 1 
          ELSE 0 
        END) AS init_first72h,
    MAX(CASE 
          WHEN LOWER(p.drug) LIKE '%glp-1%' OR 
               LOWER(p.drug) LIKE '%semaglutide%' OR 
               LOWER(p.drug) LIKE '%liraglutide%' OR 
               LOWER(p.drug) LIKE '%dulaglutide%' OR 
               LOWER(p.drug) LIKE '%exenatide%' OR 
               LOWER(p.drug) LIKE '%tirzepatide%' 
          AND 
          (LOWER(p.route) LIKE '%subcut%' OR 
           LOWER(p.route) LIKE '%intramuscular%' OR 
           LOWER(p.route) LIKE '%intravenous%')
          AND p.starttime BETWEEN a.last48h_start AND a.last48h_end
          THEN 1 
          ELSE 0 
        END) AS init_last48h
  FROM admission_periods a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    ON a.hadm_id = p.hadm_id
    AND p.starttime IS NOT NULL  -- Ensure prescription was started
  GROUP BY a.hadm_id, a.first72h_start, a.first72h_end, a.last48h_start, a.last48h_end
)
SELECT 
  (SUM(g.init_first72h) * 100.0 / COUNT(*)) AS rate_first72h,
  (SUM(g.init_last48h) * 100.0 / COUNT(*)) AS rate_last48h,
  ABS((SUM(g.init_first72h) * 100.0 / COUNT(*)) - (SUM(g.init_last48h) * 100.0 / COUNT(*))) AS abs_diff_pp
FROM glp1_flags g
INNER JOIN diagnoses d 
  ON g.hadm_id = d.hadm_id
WHERE d.has_t2dm = 1 AND d.has_hf = 1;