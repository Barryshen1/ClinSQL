WITH
-- Define sepsis ICD codes (common sepsis codes)
sepsis_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%sepsis%'
     OR LOWER(long_title) LIKE '%septicemia%'
     OR LOWER(long_title) LIKE '%septic shock%'
),

-- Get female patients aged 43-53 with sepsis admissions
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN sepsis_codes s
    ON d.icd_code = s.icd_code AND d.icd_version = s.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.admission_type NOT LIKE '%EMERGENCY%'
),

-- Get critical lab events in first 72 hours
critical_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.itemid,
    l.valuenum,
    l.valueuom,
    d.label,
    l.ref_range_lower,
    l.ref_range_upper,
    CASE
      WHEN (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
           AND l.ref_range_lower IS NOT NULL
           AND l.ref_range_upper IS NOT NULL
      THEN 1
      ELSE 0
    END AS is_critical
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  JOIN cohort c
    ON l.subject_id = c.subject_id AND l.hadm_id = c.hadm_id
  WHERE l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
),

-- Count critical events per admission
critical_counts AS (
  SELECT
    hadm_id,
    SUM(is_critical) AS critical_event_count
  FROM critical_labs
  GROUP BY hadm_id
),

-- Calculate statistics
stats AS (
  SELECT
    COUNT(DISTINCT hadm_id) AS cohort_size,
    AVG(critical_event_count) AS mean_critical_events,
    AVG(los_hours) AS mean_los_hours,
    SUM(hospital_expire_flag) * 100.0 / COUNT(DISTINCT hadm_id) AS mortality_rate,
    PERCENTILE_CONT(critical_event_count, 0.25) AS p25_instability_score
  FROM critical_counts c
  JOIN cohort co ON c.hadm_id = co.hadm_id
)

-- Final result
SELECT
  cohort_size,
  mean_critical_events,
  mean_los_hours,
  mortality_rate,
  p25_instability_score
FROM stats;