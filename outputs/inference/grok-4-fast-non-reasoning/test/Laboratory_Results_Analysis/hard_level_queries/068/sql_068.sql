WITH septic_codes AS (
  -- ICD-10 codes for septic shock
  SELECT icd_code 
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
  WHERE icd_version = '10' 
    AND (long_title LIKE '%severe sepsis with septic shock%' 
         OR long_title LIKE '%septic shock%' 
         OR icd_code LIKE 'R65.2%')
),

cohort AS (
  -- Septic shock female cohort aged 89-99
  SELECT DISTINCT p.subject_id, p.gender, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN septic_codes s ON d.icd_code = s.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
    AND a.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE')
    AND d.icd_version = '10'
),

general_cohort AS (
  -- General female inpatients aged 89-99 (no septic filter)
  SELECT DISTINCT p.subject_id, p.gender, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
    AND a.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE')
),

first_icu AS (
  -- First ICU stay per hadm_id in cohort
  SELECT c.subject_id, c.hadm_id, i.stay_id, i.intime,
         ROW_NUMBER() OVER (PARTITION BY c.hadm_id ORDER BY i.intime) AS rn
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id
),

vital_abnormals AS (
  -- Binary flags for vital abnormalities (any occurrence in first 48h)
  SELECT 
    f.stay_id,
    MAX(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS hr_abnormal,
    MAX(CASE WHEN ce.itemid = 220179 AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS sbp_abnormal,
    MAX(CASE WHEN ce.itemid = 618 AND ce.valuenum > 30 THEN 1 ELSE 0 END) AS rr_abnormal
  FROM first_icu f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON f.stay_id = ce.stay_id 
    AND ce.charttime >= f.intime AND ce.charttime < DATE_ADD(f.intime, INTERVAL 2 DAY)
    AND ce.itemid IN (220045, 220179, 618)
    AND ce.valuenum IS NOT NULL
  WHERE f.rn = 1
  GROUP BY f.stay_id
),

lab_abnormals_icu AS (
  -- Binary flags for lab abnormalities (any occurrence in first 48h)
  SELECT 
    f.stay_id,
    MAX(CASE WHEN le.itemid = 50810 AND le.valuenum > 2 THEN 1 ELSE 0 END) AS lactate_abnormal,
    MAX(CASE WHEN le.itemid = 50912 AND le.valuenum > 1.2 THEN 1 ELSE 0 END) AS creat_abnormal,
    MAX(CASE WHEN le.itemid = 26464 AND (le.valuenum < 4 OR le.valuenum > 12) THEN 1 ELSE 0 END) AS wbc_abnormal,
    MAX(CASE WHEN le.itemid = 50516 AND le.valuenum < 150 THEN 1 ELSE 0 END) AS plt_abnormal
  FROM first_icu f
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON f.subject_id = le.subject_id AND f.hadm_id = le.hadm_id
    AND le.charttime >= f.intime AND le.charttime < DATE_ADD(f.intime, INTERVAL 2 DAY)
    AND le.itemid IN (50810, 50912, 26464, 50516)
    AND le.valuenum IS NOT NULL
  WHERE f.rn = 1
  GROUP BY f.stay_id
),

instability_scores AS (
  -- Sum unique abnormal categories
  SELECT 
    v.stay_id,
    (COALESCE(v.hr_abnormal, 0) + COALESCE(v.sbp_abnormal, 0) + COALESCE(v.rr_abnormal, 0) +
     COALESCE(l.lactate_abnormal, 0) + COALESCE(l.creat_abnormal, 0) + COALESCE(l.wbc_abnormal, 0) + COALESCE(l.plt_abnormal, 0)) AS instability_score
  FROM vital_abnormals v
  FULL OUTER JOIN lab_abnormals_icu l ON v.stay_id = l.stay_id
),

septic_summary AS (
  -- Patient-level data for septic cohort (with scores, LOS)
  SELECT 
    c.hadm_id,
    COALESCE(is.instability_score, 0) AS instability_score,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    c.hospital_expire_flag
  FROM cohort c
  LEFT JOIN first_icu f ON c.hadm_id = f.hadm_id AND f.rn = 1
  LEFT JOIN instability_scores is ON f.stay_id = is.stay_id
),

lab_abnormals_sepsis AS (
  -- Abnormal labs frequency for septic cohort (full admission)
  SELECT 
    SUM(CASE WHEN le.itemid = 50810 AND le.valuenum > 2 THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT c.subject_id) AS lactate_abnormal_pct,
    SUM(CASE WHEN le.itemid = 50912 AND le.valuenum > 1.2 THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT c.subject_id) AS creatinine_abnormal_pct,
    SUM(CASE WHEN le.itemid = 26464 AND (le.valuenum < 4 OR le.valuenum > 12) THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT c.subject_id) AS wbc_abnormal_pct,
    SUM(CASE WHEN le.itemid = 50516 AND le.valuenum < 150 THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT c.subject_id) AS platelets_abnormal_pct
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON c.subject_id = le.subject_id AND c.hadm_id = le.hadm_id
    AND le.itemid IN (50810, 50912, 26464, 50516)
    AND le.valuenum IS NOT NULL
),

lab_abnormals_general AS (
  -- Same for general cohort
  SELECT 
    SUM(CASE WHEN le.itemid = 50810 AND le.valuenum > 2 THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT g.subject_id) AS lactate_abnormal_pct,
    SUM(CASE WHEN le.itemid = 50912 AND le.valuenum > 1.2 THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT g.subject_id) AS creatinine_abnormal_pct,
    SUM(CASE WHEN le.itemid = 26464 AND (le.valuenum < 4 OR le.valuenum > 12) THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT g.subject_id) AS wbc_abnormal_pct,
    SUM(CASE WHEN le.itemid = 50516 AND le.valuenum < 150 THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT g.subject_id) AS platelets_abnormal_pct
  FROM general_cohort g
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON g.subject_id = le.subject_id AND g.hadm_id = le.hadm_id
    AND le.itemid IN (50810, 50912, 26464, 50516)
    AND le.valuenum IS NOT NULL
),

septic_agg AS (
  SELECT 
    PERCENTILE_CONT(0.25, 0) OVER(ORDER BY instability_score) AS instability_q1,
    PERCENTILE_CONT(0.50, 0) OVER(ORDER BY instability_score) AS instability_median,
    PERCENTILE_CONT(0.75, 0) OVER(ORDER BY instability_score) AS instability_q3,
    PERCENTILE_CONT(0.75, 0) OVER(ORDER BY instability_score) - PERCENTILE_CONT(0.25, 0) OVER(ORDER BY instability_score) AS iqr,
    AVG(los_days) AS los_mean_days,
    PERCENTILE_CONT(los_days, 0.50, 0) OVER(ORDER BY los_days) AS los_median_days,
    AVG(hospital_expire_flag) * 100 AS mortality_pct
  FROM septic_summary
),

general_agg AS (
  SELECT 
    AVG(DATE_DIFF(dischtime, admittime, DAY)) AS los_mean_days_general,
    PERCENTILE_CONT(DATE_DIFF(dischtime, admittime, DAY), 0.50) AS los_median_days_general,
    AVG(hospital_expire_flag) * 100 AS mortality_pct_general
  FROM general_cohort
)

-- Main summary
SELECT 
  s.instability_q1,
  s.instability_median,
  s.instability_q3,
  s.iqr,
  s.los_mean_days,
  s.los_median_days,
  s.mortality_pct,
  g.los_mean_days_general,
  g.los_median_days_general,
  g.mortality_pct_general,
  ss.lactate_abnormal_pct AS sepsis_lactate_abnormal_pct,
  gs.lactate_abnormal_pct AS general_lactate_abnormal_pct,
  ss.creatinine_abnormal_pct AS sepsis_creatinine_abnormal_pct,
  gs.creatinine_abnormal_pct AS general_creatinine_abnormal_pct,
  ss.wbc_abnormal_pct AS sepsis_wbc_abnormal_pct,
  gs.wbc_abnormal_pct AS general_wbc_abnormal_pct,
  ss.platelets_abnormal_pct AS sepsis_platelets_abnormal_pct,
  gs.platelets_abnormal_pct AS general_platelets_abnormal_pct
FROM septic_agg s
CROSS JOIN general_agg g
CROSS JOIN lab_abnormals_sepsis ss
CROSS JOIN lab_abnormals_general gs;