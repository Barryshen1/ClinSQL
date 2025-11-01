WITH 
-- Step 1: Identify the cohort based on age, gender, and sepsis diagnosis
cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 43 AND 53
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE (icd_version = 9 AND icd_code IN ('99591', '99592')) 
         OR (icd_version = 10 AND icd_code LIKE 'R65%')
    )
),

-- Step 2: Count critical lab events in the first 72 hours
critical_lab_events AS (
  SELECT 
    c.hadm_id,
    COUNT(*) AS critical_event_count
  FROM 
    cohort c
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` l ON c.hadm_id = l.hadm_id
  WHERE 
    l.charttime IS NOT NULL
    AND TIMESTAMP_DIFF(l.charttime, c.admittime, HOUR) <= 72
    AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
  GROUP BY 
    c.hadm_id
),

-- Step 3: Calculate required statistics
stats AS (
  SELECT 
    COUNT(DISTINCT c.hadm_id) AS cohort_size,
    PERCENTILE_CONT(cle.critical_event_count, 0.25) AS percentile_25_critical_events,
    AVG(cle.critical_event_count) AS mean_critical_events,
    AVG(TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR)) AS mean_los_hours,
    SUM(CASE WHEN c.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS mortality_rate
  FROM 
    cohort c
  JOIN 
    critical_lab_events cle ON c.hadm_id = cle.hadm_id
)

-- Final query to fetch the required statistics
SELECT 
  cohort_size,
  percentile_25_critical_events,
  mean_critical_events,
  mean_los_hours,
  mortality_rate
FROM 
  stats
LIMIT 1;