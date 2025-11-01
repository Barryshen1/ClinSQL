WITH patients_female_age AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 65 AND 75
),
admissions_female AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    patients_female_age pfa ON a.subject_id = pfa.subject_id
),
pancreatitis_hadms AS (
  SELECT DISTINCT 
    di.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did ON di.icd_code = did.icd_code 
    AND di.icd_version = did.icd_version
  WHERE 
    LOWER(did.long_title) LIKE '%acute%' 
    AND LOWER(did.long_title) LIKE '%pancreatitis%'
),
pancreatitis_cohort AS (
  SELECT 
    af.*,
    TIMESTAMP_DIFF(af.dischtime, af.admittime, HOUR) / 24.0 AS los_days
  FROM 
    admissions_female af
  INNER JOIN 
    pancreatitis_hadms ph ON af.hadm_id = ph.hadm_id
),
pancreatitis_scores AS (
  SELECT 
    le.hadm_id,
    COUNT(*) AS instability_score
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN 
    pancreatitis_cohort pc ON le.subject_id = pc.subject_id AND le.hadm_id = pc.hadm_id
  WHERE 
    le.charttime >= pc.admittime
    AND le.charttime < TIMESTAMP_ADD(pc.admittime, INTERVAL 48 HOUR)
    AND le.flag = 'abnormal'
  GROUP BY 
    le.hadm_id
),
pancreatitis_with_scores AS (
  SELECT 
    pc.*,
    COALESCE(ps.instability_score, 0) AS instability_score,
    NTILE(5) OVER (ORDER BY COALESCE(ps.instability_score, 0) ASC) AS quintile
  FROM 
    pancreatitis_cohort pc
  LEFT JOIN 
    pancreatitis_scores ps ON pc.hadm_id = ps.hadm_id
),
general_cohort AS (
  SELECT 
    af.*,
    TIMESTAMP_DIFF(af.dischtime, af.admittime, HOUR) / 24.0 AS los_days
  FROM 
    admissions_female af
),
general_scores AS (
  SELECT 
    le.hadm_id,
    COUNT(*) AS instability_score
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN 
    general_cohort gc ON le.subject_id = gc.subject_id AND le.hadm_id = gc.hadm_id
  WHERE 
    le.charttime >= gc.admittime
    AND le.charttime < TIMESTAMP_ADD(gc.admittime, INTERVAL 48 HOUR)
    AND le.flag = 'abnormal'
  GROUP BY 
    le.hadm_id
),
general_with_scores AS (
  SELECT 
    COALESCE(gs.instability_score, 0) AS instability_score
  FROM 
    general_cohort gc
  LEFT JOIN 
    general_scores gs ON gc.hadm_id = gs.hadm_id
),
general_critical_pct AS (
  SELECT 
    (SUM(CASE WHEN instability_score > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS general_pct_critical
  FROM 
    general_with_scores
)
SELECT 
  quintile,
  COUNT(*) AS count,
  ROUND(AVG(instability_score), 2) AS mean_instability,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS mortality_pct,
  ROUND((SUM(CASE WHEN instability_score > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)), 2) AS pct_critical_pancreatitis,
  ROUND((SELECT general_pct_critical FROM general_critical_pct), 2) AS pct_critical_general
FROM 
  pancreatitis_with_scores
GROUP BY 
  quintile
ORDER BY 
  quintile;