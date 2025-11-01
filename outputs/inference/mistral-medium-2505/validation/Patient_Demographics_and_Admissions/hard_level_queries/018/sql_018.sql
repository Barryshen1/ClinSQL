WITH
-- Define femoral neck fracture ICD-10 codes
femoral_fracture_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'S72.0%' OR icd_code LIKE 'S72.1%'
),

-- Get qualifying patients (female, 58-68, Medicare, ED admission)
qualifying_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN femoral_fracture_codes f
    ON d.icd_code = f.icd_code
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND (a.insurance = 'Medicare' OR a.insurance LIKE '%Medicare%')
    AND a.admission_type = 'EMERGENCY'
    AND d.seq_num = 1  -- Principal diagnosis
    AND a.hospital_expire_flag = 0  -- Exclude in-hospital deaths
),

-- Identify index admissions (first qualifying admission per patient)
index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    los_days,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS admission_rank
  FROM qualifying_patients
),

-- Get only the first qualifying admission per patient
first_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    los_days
  FROM index_admissions
  WHERE admission_rank = 1
),

-- Find 30-day readmissions
readmissions AS (
  SELECT
    f.subject_id,
    f.hadm_id AS index_hadm_id,
    f.admittime AS index_admittime,
    f.dischtime AS index_dischtime,
    f.los_days AS index_los,
    a.hadm_id AS readmit_hadm_id,
    a.admittime AS readmit_admittime,
    TIMESTAMP_DIFF(a.admittime, f.dischtime, DAY) AS days_to_readmit
  FROM first_admissions f
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON f.subject_id = a.subject_id
    AND a.admittime > f.dischtime
    AND a.admittime <= TIMESTAMP_ADD(f.dischtime, INTERVAL 30 DAY)
  WHERE a.hadm_id != f.hadm_id  -- Exclude same admission
),

-- Flag patients with readmissions
readmission_flags AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.los_days,
    CASE WHEN r.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_readmission
  FROM first_admissions f
  LEFT JOIN readmissions r
    ON f.subject_id = r.subject_id
),

-- Count total patients to check if we have data
patient_counts AS (
  SELECT
    COUNT(*) AS total_patients,
    COUNT(CASE WHEN has_readmission = 1 THEN 1 END) AS readmitted_patients,
    COUNT(CASE WHEN los_days > 8 THEN 1 END) AS long_stay_patients
  FROM readmission_flags
)

-- Calculate final metrics
SELECT
  -- 30-day readmission rate
  COALESCE(SAFE_DIVIDE(readmitted_patients, total_patients) * 100, 0) AS readmission_rate_percentage,

  -- Median LOS for readmitted vs non-readmitted
  (SELECT APPROX_QUANTILES(los_days, 2)[OFFSET(1)] FROM readmission_flags WHERE has_readmission = 1) AS median_los_readmitted,
  (SELECT APPROX_QUANTILES(los_days, 2)[OFFSET(1)] FROM readmission_flags WHERE has_readmission = 0) AS median_los_non_readmitted,

  -- Percent of index stays >8 days
  COALESCE(SAFE_DIVIDE(long_stay_patients, total_patients) * 100, 0) AS percent_stays_gt_8_days

FROM patient_counts;