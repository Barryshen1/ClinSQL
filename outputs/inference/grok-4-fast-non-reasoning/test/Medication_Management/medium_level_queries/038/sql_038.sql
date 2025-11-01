WITH cohort AS (
  -- Define cohort: males 57-67 with primary dx of diabetes + acute HF
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_ADD(a.admittime, INTERVAL 72 HOUR) AS window72_end,
    -- Final 24h start only if stay >=72h
    CASE 
      WHEN a.dischtime >= DATE_ADD(a.admittime, INTERVAL 72 HOUR) 
      THEN DATE_SUB(a.dischtime, INTERVAL 24 HOUR)
      ELSE NULL 
    END AS final24_start
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND a.admission_type != 'OBSERVATION'
    AND SAFE_CAST(d.seq_num AS INT64) = 1
    AND (
      -- Primary dx: diabetes (ICD-10 E08-E13)
      (d.icd_version = '10' AND d.icd_code BETWEEN 'E08' AND 'E13')
      OR 
      -- Acute HF (ICD-10 I50*)
      (d.icd_version = '10' AND d.icd_code LIKE 'I50%')
    )
    -- One admission per patient: latest
    AND a.admittime = (
      SELECT MAX(a2.admittime)
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = a.subject_id AND a2.admission_type != 'OBSERVATION'
    )
    -- Exclude early deaths
    AND (a.deathtime IS NULL OR a.deathtime >= DATE_ADD(a.admittime, INTERVAL 72 HOUR))
),

glp1_orders AS (
  -- GLP-1 prescriptions (common names; extend list as needed)
  SELECT DISTINCT 
    r.subject_id,
    r.hadm_id,
    r.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` r
  INNER JOIN cohort c
    ON r.subject_id = c.subject_id AND r.hadm_id = c.hadm_id
  WHERE r.drug IS NOT NULL
    AND LOWER(r.drug) IN (
      'semaglutide', 'ozempic', 'rybelsus', 'wegovy',
      'liraglutide', 'victoza', 'saxenda',
      'dulaglutide', 'trulicity',
      'exenatide', 'byetta', 'bydureon',
      'albiglutide', 'tanzeum'  -- Less common, but include
    )
    AND r.starttime IS NOT NULL
),

first72 AS (
  SELECT 
    COUNT(DISTINCT go.subject_id) AS n_first72
  FROM glp1_orders go
  INNER JOIN cohort c
    ON go.subject_id = c.subject_id
  WHERE go.starttime >= c.admittime 
    AND go.starttime < c.window72_end
),

final24 AS (
  SELECT 
    COUNT(DISTINCT go.subject_id) AS n_final24
  FROM glp1_orders go
  INNER JOIN cohort c
    ON go.subject_id = c.subject_id
  WHERE c.final24_start IS NOT NULL
    AND go.starttime >= c.final24_start
    AND go.starttime < c.dischtime
),

totals AS (
  SELECT 
    (SELECT COUNT(DISTINCT subject_id) FROM cohort) AS n_total,
    (SELECT n_first72 FROM first72) AS n_first72,
    (SELECT n_final24 FROM final24) AS n_final24
)

SELECT 
  n_total AS total_patients,
  ROUND((n_first72 / n_total * 100), 2) AS first72h_prevalence_pct,
  ROUND((n_final24 / n_total * 100), 2) AS final24h_prevalence_pct,
  ROUND((n_final24 / n_total * 100) - (n_first72 / n_total * 100), 2) AS absolute_change_pct,
  ROUND(((n_final24 / n_total * 100) / (n_first72 / n_total * 100) - 1) * 100, 2) AS relative_change_pct
FROM totals;