WITH index_adms AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
    AND diag.seq_num = '1'
  WHERE p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 58 AND 68
    AND a.admission_location = 'EMERGENCY ROOM'
    AND diag.icd_version = '10'
    AND diag.icd_code LIKE 'S72.0%'
),
alive_index AS (
  SELECT * 
  FROM index_adms 
  WHERE hospital_expire_flag = 0
),
cohort AS (
  SELECT 
    ai.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` ra
        WHERE ra.subject_id = ai.subject_id
          AND ra.hadm_id != ai.hadm_id
          AND ra.admittime > ai.dischtime
          AND ra.admittime <= TIMESTAMP_ADD(ai.dischtime, INTERVAL 30 DAY)
      ) THEN 1 
      ELSE 0 
    END AS is_readmitted
  FROM alive_index ai
)
SELECT 
  -- 30-day readmission rate (among alive at discharge)
  COUNT(*) AS n_index_alive,
  SUM(is_readmitted) AS n_readmitted,
  ROUND(SAFE_DIVIDE(SUM(is_readmitted), COUNT(*)) * 100, 2) AS readmission_rate_percent,
  
  -- Median index LOS for readmitted vs. non-readmitted (alive only)
  (SELECT PERCENTILE_CONT(los_days, 0.5) FROM cohort WHERE is_readmitted = 1) AS median_los_readmitted_days,
  (SELECT PERCENTILE_CONT(los_days, 0.5) FROM cohort WHERE is_readmitted = 0) AS median_los_nonreadmitted_days,
  
  -- Percent of initial stays >8 days (all index admissions, including deaths)
  (SELECT COUNT(*) FROM index_adms) AS total_initial_stays,
  (SELECT COUNTIF(los_days > 8) FROM index_adms) AS n_stays_over_8_days,
  ROUND(SAFE_DIVIDE((SELECT COUNTIF(los_days > 8) FROM index_adms), (SELECT COUNT(*) FROM index_adms)) * 100, 2) 
    AS pct_initial_stays_over_8_days
FROM cohort;