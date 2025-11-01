WITH
  -- Define hemorrhagic stroke codes
  stroke_codes AS (
    SELECT '431' AS icd_code, 9 AS icd_version
    UNION ALL
    SELECT 'I61', 10
    UNION ALL
    SELECT 'I61.0', 10
    UNION ALL
    SELECT 'I61.1', 10
    UNION ALL
    SELECT 'I61.2', 10
    UNION ALL
    SELECT 'I61.3', 10
    UNION ALL
    SELECT 'I61.4', 10
    UNION ALL
    SELECT 'I61.5', 10
    UNION ALL
    SELECT 'I61.6', 10
    UNION ALL
    SELECT 'I61.8', 10
    UNION ALL
    SELECT 'I61.9', 10
  ),
  
  -- Cohort: male, age 70-80, hemorrhagic stroke
  cohort AS (
    SELECT DISTINCT a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
    JOIN stroke_codes sc ON di.icd_code = sc.icd_code AND di.icd_version = sc.icd_version
    WHERE p.gender = 'M'
      AND p.anchor_age >= 70 AND p.anchor_age <= 80
  ),
  
  -- First 48h lab events for all admissions with abnormal flags
  labs_48h AS (
    SELECT
      le.hadm_id,
      le.charttime,
      le.flag
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON le.hadm_id = a.hadm_id
    WHERE le.charttime >= a.admittime
      AND le.charttime <= DATETIME_ADD(a.admittime, INTERVAL 48 HOUR)
      AND le.flag IS NOT NULL
      AND le.flag IN ('abnormal', 'high', 'low')
  ),
  
  -- Critical lab counts per admission for cohort
  cohort_lab_counts AS (
    SELECT
      c.hadm_id,
      COUNT(*) AS critical_lab_count
    FROM cohort c
    LEFT JOIN labs_48h l ON c.hadm_id = l.hadm_id
    GROUP BY c.hadm_id
  ),
  
  -- Critical lab counts for general population (all admissions with lab data in first 48h)
  general_lab_counts AS (
    SELECT
      a.hadm_id,
      COUNT(*) AS critical_lab_count
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN labs_48h l ON a.hadm_id = l.hadm_id
    GROUP BY a.hadm_id
  ),
  
  -- Hospital LOS and mortality for cohort
  cohort_outcomes AS (
    SELECT
      a.hadm_id,
      DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
      a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    WHERE a.hadm_id IN (SELECT hadm_id FROM cohort)
  )

-- Final output
SELECT
  -- 25th percentile of lab instability score (critical lab count) in cohort
  APPROX_QUANTILES(clc.critical_lab_count, 100)[OFFSET(25)] AS cohort_lab_instability_25th_percentile,
  
  -- Mean critical lab event rate (per admission) in cohort
  AVG(clc.critical_lab_count) AS cohort_critical_lab_rate,
  
  -- Mean critical lab event rate in general inpatient population
  (SELECT AVG(critical_lab_count) FROM general_lab_counts) AS general_critical_lab_rate,
  
  -- Mean hospital LOS for cohort
  AVG(co.los_days) AS cohort_mean_los_days,
  
  -- In-hospital mortality rate for cohort
  AVG(co.hospital_expire_flag) AS cohort_mortality_rate

FROM cohort_lab_counts clc
JOIN cohort_outcomes co ON clc.hadm_id = co.hadm_id;