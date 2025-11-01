WITH cohort AS (
  SELECT DISTINCT 
    a.subject_id, 
    a.hadm_id, 
    p.gender, 
    p.anchor_age, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE p.gender = 'M'
    AND p.anchor_age >= 89
    AND p.anchor_age <= 99
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('569.3', '569.84', '578.1')) 
      OR 
      (d.icd_version = 10 AND d.icd_code IN ('K92.1', 'K92.2'))
    )
),
patient_labs AS (
  SELECT 
    c.*,
    l.itemid, 
    l.valuenum, 
    l.valueuom, 
    l.flag, 
    l.charttime
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON c.hadm_id = l.hadm_id
  WHERE l.charttime >= c.admittime 
    AND l.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
),
instability_score AS (
  SELECT 
    hadm_id, 
    COUNT(CASE WHEN flag = 'abnormal' THEN 1 END) AS instability_score_raw
  FROM patient_labs
  GROUP BY hadm_id
),
critical_flag AS (
  SELECT 
    hadm_id,
    MAX(CASE 
      WHEN itemid = 51221 AND valuenum < 7.0 AND valueuom = 'g/dL' THEN 1
      WHEN itemid IN (50577, 51265) AND valuenum < 50 THEN 1
      WHEN itemid = 51237 AND valuenum > 1.5 THEN 1
      WHEN itemid = 50912 AND valuenum > 2.0 AND valueuom = 'mg/dL' THEN 1
      WHEN itemid = 51006 AND valuenum > 50 AND valueuom = 'mg/dL' THEN 1
      ELSE 0 
    END) AS has_critical_raw
  FROM patient_labs
  GROUP BY hadm_id
),
cohort_with_scores AS (
  SELECT 
    c.*,
    COALESCE(s.instability_score_raw, 0) AS instability_score,
    COALESCE(cr.has_critical_raw, 0) AS has_critical,
    TIMESTAMP_DIFF(
      COALESCE(c.dischtime, c.admittime),  -- Handle rare NULL dischtime
      c.admittime, 
      HOUR
    ) / 24.0 AS los_days
  FROM cohort c
  LEFT JOIN instability_score s ON c.hadm_id = s.hadm_id
  LEFT JOIN critical_flag cr ON c.hadm_id = cr.hadm_id
),
quintiled AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY instability_score ASC) AS quintile
  FROM cohort_with_scores
),
quintile_stats AS (
  SELECT 
    quintile,
    COUNT(*) AS n_patients,
    ROUND(AVG(los_days), 2) AS avg_los_days,
    ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS mortality_rate_pct,
    ROUND(AVG(CAST(has_critical AS FLOAT64)) * 100, 2) AS critical_lab_rate_pct
  FROM quintiled
  GROUP BY quintile
  ORDER BY quintile
),
-- General inpatient computations (all admissions)
all_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),
general_labs AS (
  SELECT 
    l.subject_id, 
    l.hadm_id, 
    l.itemid, 
    l.valuenum, 
    l.valueuom,
    l.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN all_admissions aa 
    ON l.hadm_id = aa.hadm_id
  WHERE l.charttime >= aa.admittime 
    AND l.charttime < TIMESTAMP_ADD(aa.admittime, INTERVAL 72 HOUR)
),
general_critical AS (
  SELECT 
    hadm_id,
    MAX(CASE 
      WHEN itemid = 51221 AND valuenum < 7.0 AND valueuom = 'g/dL' THEN 1
      WHEN itemid IN (50577, 51265) AND valuenum < 50 THEN 1
      WHEN itemid = 51237 AND valuenum > 1.5 THEN 1
      WHEN itemid = 50912 AND valuenum > 2.0 AND valueuom = 'mg/dL' THEN 1
      WHEN itemid = 51006 AND valuenum > 50 AND valueuom = 'mg/dL' THEN 1
      ELSE 0 
    END) AS has_critical
  FROM general_labs
  GROUP BY hadm_id
),
general_rate AS (
  SELECT 
    ROUND(AVG(CAST(COALESCE(gc.has_critical, 0) AS FLOAT64)) * 100, 2) AS general_critical_rate_pct,
    COUNT(DISTINCT aa.hadm_id) AS total_inpatients
  FROM all_admissions aa
  LEFT JOIN general_critical gc ON aa.hadm_id = gc.hadm_id
)
SELECT 
  qs.*,
  gr.general_critical_rate_pct
FROM quintile_stats qs
CROSS JOIN general_rate gr;