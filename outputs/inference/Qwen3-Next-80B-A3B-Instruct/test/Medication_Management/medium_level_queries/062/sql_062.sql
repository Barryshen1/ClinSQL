WITH cohort AS (
  SELECT DISTINCT p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d1 ON a.hadm_id = d1.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d2 ON a.hadm_id = d2.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND d1.icd_version = 10 AND d1.icd_code LIKE 'E1%'
    AND d2.icd_version = 10 AND d2.icd_code LIKE 'I50%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime + INTERVAL '72' HOUR  -- Only include stays ≥72h
),

glp1_prescriptions AS (
  SELECT p.hadm_id, p.starttime
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
  INNER JOIN cohort c ON p.hadm_id = c.hadm_id
  WHERE LOWER(p.drug) IN (
    'exenatide', 'liraglutide', 'semaglutide', 'dulaglutide', 'lixisenatide', 'albiglutide'
  )
    AND (
      LOWER(p.route) LIKE '%sc%' 
      OR LOWER(p.route) LIKE '%subcut%' 
      OR LOWER(p.route) LIKE '%inj%' 
      OR LOWER(p.route) LIKE '%inject%'
    )
    AND LOWER(p.route) NOT LIKE '%oral%'  -- Exclude oral formulations
    AND p.starttime IS NOT NULL
),

initiation_flags AS (
  SELECT 
    c.hadm_id,
    MAX(CASE 
      WHEN gp.starttime BETWEEN c.admittime AND c.admittime + INTERVAL '72' HOUR 
      THEN 1 ELSE 0 
    END) AS glp1_init_first_72h,
    MAX(CASE 
      WHEN gp.starttime BETWEEN c.dischtime - INTERVAL '72' HOUR AND c.dischtime 
      THEN 1 ELSE 0 
    END) AS glp1_init_final_72h
  FROM cohort c
  LEFT JOIN glp1_prescriptions gp ON c.hadm_id = gp.hadm_id
  GROUP BY c.hadm_id, c.admittime, c.dischtime
)

SELECT 
  AVG(glp1_init_first_72h) AS rate_first_72h,
  AVG(glp1_init_final_72h) AS rate_final_72h,
  AVG(glp1_init_final_72h) - AVG(glp1_init_first_72h) AS absolute_change,
  CASE 
    WHEN AVG(glp1_init_first_72h) > 0 
    THEN (AVG(glp1_init_final_72h) - AVG(glp1_init_first_72h)) / AVG(glp1_init_first_72h)
    ELSE NULL 
  END AS relative_change
FROM initiation_flags;