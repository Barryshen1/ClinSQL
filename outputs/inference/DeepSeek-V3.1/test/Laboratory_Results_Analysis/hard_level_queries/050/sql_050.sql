WITH ards_cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 40 AND 50
    AND (
      (diag.icd_version = 9 AND diag.icd_code = '518.82') OR
      (diag.icd_version = 10 AND diag.icd_code = 'J80')
    )
),

-- For all female patients aged 40-50, get abnormal lab count in first 72h
all_patients_lab_score AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    COUNT(CASE WHEN le.flag IS NOT NULL THEN 1 ELSE NULL END) AS instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON adm.hadm_id = le.hadm_id
      AND le.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 72 HOUR)
      AND le.flag IS NOT NULL  -- only abnormal labs
  WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 40 AND 50
  GROUP BY adm.subject_id, adm.hadm_id
),

-- Get the 75th percentile instability score for ARDS patients
ards_percentile AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75_score
  FROM all_patients_lab_score a
  INNER JOIN ards_cohort ac 
    ON a.hadm_id = ac.hadm_id
),

-- High-instability ARDS patients
high_instability_ards AS (
  SELECT 
    ac.*,
    a.instability_score
  FROM all_patients_lab_score a
  INNER JOIN ards_cohort ac 
    ON a.hadm_id = ac.hadm_id
  CROSS JOIN ards_percentile
  WHERE a.instability_score >= ards_percentile.p75_score
),

-- Control group: non-ARDS patients (same age and gender)
control_group AS (
  SELECT 
    a.hadm_id,
    a.instability_score
  FROM all_patients_lab_score a
  WHERE a.hadm_id NOT IN (SELECT hadm_id FROM ards_cohort)
)

-- Final output
SELECT 
  (SELECT p75_score FROM ards_percentile) AS p75_instability_score,
  COUNT(*) AS num_high_instability_ards,
  SUM(hia.hospital_expire_flag) AS mortality_count,
  AVG(hia.los_days) AS mean_los_days,
  AVG(hia.instability_score) AS avg_critical_labs_ards,
  (SELECT AVG(instability_score) FROM control_group) AS avg_critical_labs_control
FROM high_instability_ards hia;