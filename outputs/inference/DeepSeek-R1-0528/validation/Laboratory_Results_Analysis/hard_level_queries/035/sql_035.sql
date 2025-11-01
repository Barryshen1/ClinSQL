WITH base_admissions AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
),
filtered_admissions AS (
  SELECT 
    subject_id, 
    hadm_id, 
    admittime, 
    dischtime, 
    hospital_expire_flag,
    age_admit
  FROM base_admissions
  WHERE age_admit BETWEEN 78 AND 88
),
stroke_codes AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND (icd_code LIKE '433%' OR icd_code LIKE '434%' OR icd_code = '436')) OR
    (icd_version = 10 AND (icd_code LIKE 'I63%' OR icd_code = 'I64'))
),
admissions_with_stroke AS (
  SELECT 
    f.*,
    CASE WHEN s.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_stroke
  FROM filtered_admissions f
  LEFT JOIN stroke_codes s
    ON f.hadm_id = s.hadm_id
),
critical_lab_counts AS (
  SELECT 
    a.hadm_id,
    COUNT(l.labevent_id) AS critical_lab_count
  FROM admissions_with_stroke a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.hadm_id = l.hadm_id
    AND a.subject_id = l.subject_id
    AND l.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
    AND l.flag IS NOT NULL  -- Critical = any flagged abnormal result
  GROUP BY a.hadm_id
),
cohort_data AS (
  SELECT 
    a.hadm_id,
    c.critical_lab_count,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag
  FROM admissions_with_stroke a
  INNER JOIN critical_lab_counts c
    ON a.hadm_id = c.hadm_id
  WHERE a.is_stroke = 1  -- Stroke cohort
),
control_data AS (
  SELECT 
    c.critical_lab_count
  FROM admissions_with_stroke a
  INNER JOIN critical_lab_counts c
    ON a.hadm_id = c.hadm_id
  WHERE a.is_stroke = 0  -- Control group (no stroke)
),
cohort_summary AS (
  SELECT
    MIN(critical_lab_count) AS min_72hr_lab_instability_score,
    AVG(critical_lab_count) AS cohort_avg_critical_lab_events,
    AVG(los_days) AS cohort_avg_los,
    AVG(hospital_expire_flag) AS cohort_mortality_rate
  FROM cohort_data
),
control_summary AS (
  SELECT
    AVG(critical_lab_count) AS control_avg_critical_lab_events
  FROM control_data
)
SELECT
  min_72hr_lab_instability_score,
  cohort_avg_critical_lab_events,
  control_avg_critical_lab_events,
  cohort_avg_los,
  cohort_mortality_rate
FROM cohort_summary, control_summary;