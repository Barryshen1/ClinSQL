WITH patients_filtered AS (
  SELECT 
    subject_id,
    anchor_age,
    anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
),
admissions_filtered AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients_filtered p
    ON a.subject_id = p.subject_id
  WHERE 
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 44 AND 54
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
ami_cohort_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.los
  FROM admissions_filtered a
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE 
      d.hadm_id = a.hadm_id
      AND d.icd_version = 10
      AND d.icd_code IN (
        'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I21.9',
        'I22.0', 'I22.1', 'I22.2', 'I22.8', 'I22.9'
      )
  )
),
general_cohort_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM admissions_filtered a
  WHERE NOT EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE 
      d.hadm_id = a.hadm_id
      AND d.icd_version = 10
      AND d.icd_code IN (
        'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I21.9',
        'I22.0', 'I22.1', 'I22.2', 'I22.8', 'I22.9'
      )
  )
),
ami_critical_labs AS (
  SELECT 
    a.hadm_id,
    COUNT(l.labevent_id) AS critical_lab_count
  FROM ami_cohort_admissions a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.hadm_id = l.hadm_id
    AND l.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
    AND l.flag IN ('critical', 'critical high', 'critical low')
  GROUP BY a.hadm_id
),
general_critical_labs AS (
  SELECT 
    a.hadm_id,
    COUNT(l.labevent_id) AS critical_lab_count
  FROM general_cohort_admissions a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.hadm_id = l.hadm_id
    AND l.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
    AND l.flag IN ('critical', 'critical high', 'critical low')
  GROUP BY a.hadm_id
),
ami_cohort AS (
  SELECT 
    a.hadm_id,
    COALESCE(c.critical_lab_count, 0) AS critical_lab_count,
    a.los,
    a.hospital_expire_flag
  FROM ami_cohort_admissions a
  LEFT JOIN ami_critical_labs c
    ON a.hadm_id = c.hadm_id
),
general_cohort AS (
  SELECT 
    hadm_id,
    COALESCE(critical_lab_count, 0) AS critical_lab_count
  FROM general_critical_labs
),
ami_stats AS (
  SELECT
    APPROX_QUANTILES(critical_lab_count, 1000)[OFFSET(750)] AS percentile_75,
    AVG(critical_lab_count) AS ami_critical_lab_avg,
    AVG(los) AS ami_los_avg,
    AVG(hospital_expire_flag) AS ami_mortality_rate
  FROM ami_cohort
),
general_stats AS (
  SELECT
    AVG(critical_lab_count) AS general_critical_lab_avg
  FROM general_cohort
)
SELECT
  s.percentile_75,
  s.ami_critical_lab_avg,
  g.general_critical_lab_avg,
  s.ami_los_avg,
  s.ami_mortality_rate
FROM ami_stats s
CROSS JOIN general_stats g;