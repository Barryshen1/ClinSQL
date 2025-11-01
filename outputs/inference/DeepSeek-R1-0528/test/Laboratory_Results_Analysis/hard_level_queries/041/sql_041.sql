WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age, 
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
),
heart_failure AS (
  SELECT DISTINCT 
    subject_id, 
    hadm_id 
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
  WHERE 
    (icd_version = 9 AND icd_code LIKE '428%') 
    OR (icd_version = 10 AND icd_code LIKE 'I50%')
),
cohort_hf AS (
  SELECT 
    c.* 
  FROM cohort c
  INNER JOIN heart_failure hf
    ON c.subject_id = hf.subject_id AND c.hadm_id = hf.hadm_id
  WHERE c.age_at_admit BETWEEN 54 AND 64
),
lab_events_first48 AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    COUNT(*) AS critical_labs_48h
  FROM cohort_hf c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id AND c.hadm_id = le.hadm_id
  WHERE 
    le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
    AND le.flag IN ('abnormal', 'delta')
  GROUP BY c.subject_id, c.hadm_id
),
lab_events_entire_stay AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    COUNT(*) AS total_critical_labs
  FROM cohort_hf c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id AND c.hadm_id = le.hadm_id
  WHERE 
    le.charttime BETWEEN c.admittime AND c.dischtime
    AND le.flag IN ('abnormal', 'delta')
  GROUP BY c.subject_id, c.hadm_id
),
cohort_with_labs AS (
  SELECT 
    c.*,
    COALESCE(l48.critical_labs_48h, 0) AS score_48h,
    COALESCE(les.total_critical_labs, 0) AS total_critical_labs,
    DATETIME_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days
  FROM cohort_hf c
  LEFT JOIN lab_events_first48 l48
    ON c.subject_id = l48.subject_id AND c.hadm_id = l48.hadm_id
  LEFT JOIN lab_events_entire_stay les
    ON c.subject_id = les.subject_id AND c.hadm_id = les.hadm_id
),
percentile AS (
  SELECT 
    APPROX_QUANTILES(score_48h, 100)[OFFSET(95)] AS p95
  FROM cohort_with_labs
),
cohort_groups AS (
  SELECT 
    c.*,
    CASE 
      WHEN score_48h >= (SELECT p95 FROM percentile) THEN 'High'
      ELSE 'Control'
    END AS group_label
  FROM cohort_with_labs c
)
SELECT 
  group_label,
  COUNT(*) AS n_patients,
  AVG(hospital_expire_flag) * 100 AS mortality_rate_percent,
  AVG(los_days) AS mean_los_days,
  CASE 
    WHEN SUM(los_days) > 0 THEN SUM(total_critical_labs) / SUM(los_days) 
    ELSE NULL 
  END AS critical_lab_rate_per_patient_day
FROM cohort_groups
GROUP BY group_label;