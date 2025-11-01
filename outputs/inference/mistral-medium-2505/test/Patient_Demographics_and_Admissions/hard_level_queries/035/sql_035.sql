WITH
-- Get UTI diagnosis codes
uti_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%urinary tract infection%'
     OR icd_code LIKE 'N39.0%'
),

-- Get index admissions meeting criteria
index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.insurance,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  JOIN uti_codes u ON d.icd_code = u.icd_code
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'SNF'
    AND a.hospital_expire_flag = 0
),

-- Get subsequent admissions within 30 days
readmissions AS (
  SELECT
    i.subject_id,
    i.hadm_id AS index_hadm_id,
    r.hadm_id AS readmit_hadm_id,
    r.admittime AS readmit_time,
    TIMESTAMP_DIFF(r.admittime, i.dischtime, DAY) AS days_to_readmit
  FROM index_admissions i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` r ON i.subject_id = r.subject_id
  WHERE
    r.admittime > i.dischtime
    AND TIMESTAMP_DIFF(r.admittime, i.dischtime, DAY) <= 30
    AND r.hadm_id != i.hadm_id
),

-- Flag patients with readmissions
patient_readmission_status AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.los_days,
    CASE WHEN r.readmit_hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_readmission
  FROM index_admissions i
  LEFT JOIN readmissions r ON i.hadm_id = r.index_hadm_id
),

-- Calculate statistics
readmission_stats AS (
  SELECT
    has_readmission,
    COUNT(DISTINCT subject_id) AS patient_count,
    COUNT(DISTINCT hadm_id) AS stay_count,
    COUNT(DISTINCT CASE WHEN los_days > 6 THEN hadm_id END) AS long_stays,
    PERCENTILE_CONT(los_days, 0.5) AS median_los
  FROM patient_readmission_status
  GROUP BY has_readmission
)

-- Final results
SELECT
  SUM(CASE WHEN has_readmission = 1 THEN patient_count ELSE 0 END) AS readmitted_count,
  SUM(patient_count) AS total_patients,
  ROUND(SUM(CASE WHEN has_readmission = 1 THEN patient_count ELSE 0 END) * 100.0 / SUM(patient_count), 2) AS readmission_rate_pct,
  MAX(CASE WHEN has_readmission = 1 THEN median_los END) AS median_los_readmitted,
  MAX(CASE WHEN has_readmission = 0 THEN median_los END) AS median_los_not_readmitted,
  ROUND(SUM(long_stays) * 100.0 / SUM(stay_count), 2) AS pct_stays_over_6_days
FROM readmission_stats;