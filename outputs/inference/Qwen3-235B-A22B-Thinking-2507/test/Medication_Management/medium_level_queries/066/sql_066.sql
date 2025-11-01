WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    -- Age at admission: 58-68 inclusive
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 58 AND 68
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
    -- Admission duration ≥72 hours
    AND (a.dischtime - a.admittime) >= INTERVAL '72' HOUR
    -- T2DM diagnosis (ICD-10 E11.*)
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id 
        AND d.icd_version = 10 
        AND d.icd_code LIKE 'E11%'
    )
    -- Heart failure diagnosis (ICD-10 I50.*)
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id 
        AND d.icd_version = 10 
        AND d.icd_code LIKE 'I50%'
    )
),
glp1_starts AS (
  SELECT 
    p.hadm_id,
    MIN(p.starttime) AS first_glagon_start
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE LOWER(p.drug) IN (
    'exenatide', 'liraglutide', 'dulaglutide', 'semaglutide', 'lixisenatide', 'albiglutide',
    'victoza', 'saxenda', 'trulicity', 'ozempic', 'rybelsus', 'byetta', 'bydureon', 'adlyxin', 'tanzeum'
  )
    AND p.starttime IS NOT NULL
  GROUP BY p.hadm_id
),
flags AS (
  SELECT 
    c.hadm_id,
    CASE 
      WHEN g.first_glagon_start IS NOT NULL 
        AND g.first_glagon_start >= c.admittime 
        AND g.first_glagon_start <= c.admittime + INTERVAL '72' HOUR 
      THEN 1 ELSE 0 
    END AS started_first_72h,
    CASE 
      WHEN g.first_glagon_start IS NOT NULL 
        AND g.first_glagon_start >= c.dischtime - INTERVAL '12' HOUR 
        AND g.first_glagon_start <= c.dischtime 
      THEN 1 ELSE 0 
    END AS started_final_12h
  FROM cohort c
  LEFT JOIN glp1_starts g
    ON c.hadm_id = g.hadm_id
)
SELECT 
  (SUM(started_first_72h) * 100.0 / COUNT(*)) AS percent_first_72h,
  (SUM(started_final_12h) * 100.0 / COUNT(*)) AS percent_final_12h,
  ABS(
    (SUM(started_first_72h) * 100.0 / COUNT(*)) 
    - (SUM(started_final_12h) * 100.0 / COUNT(*))
  ) AS absolute_difference
FROM flags;