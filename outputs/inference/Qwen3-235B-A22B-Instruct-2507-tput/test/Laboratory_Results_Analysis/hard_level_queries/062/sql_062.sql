WITH sepsis_admissions AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), DAY) / 365.25) BETWEEN 43 AND 53
    AND di.icd_version = 10
    AND (
      di.icd_code LIKE 'A40%' OR
      di.icd_code LIKE 'A41%' OR
      di.icd_code = 'R6520' OR
      di.icd_code = 'R6521'
    )
),
critical_labs_72h AS (
  SELECT 
    sa.hadm_id,
    COUNT(*) AS critical_event_count
  FROM sepsis_admissions sa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON sa.hadm_id = le.hadm_id
  WHERE le.charttime >= sa.admittime 
    AND le.charttime < DATETIME_ADD(sa.admittime, INTERVAL 72 HOUR)
    AND LOWER(le.flag) = 'abnormal'
  GROUP BY sa.hadm_id
),
cohort_stats AS (
  SELECT
    cl.critical_event_count,
    DATETIME_DIFF(sa.dischtime, sa.admittime, HOUR) / 24.0 AS los_days,
    sa.hospital_expire_flag
  FROM critical_labs_72h cl
  JOIN sepsis_admissions sa USING (hadm_id)
)
SELECT
  APPROX_QUANTILES(critical_event_count, 100)[OFFSET(25)] AS instability_score_25th_percentile,
  AVG(critical_event_count) AS mean_critical_events_per_admission,
  AVG(los_days) AS mean_los_days,
  AVG(hospital_expire_flag) AS mortality_rate
FROM cohort_stats;