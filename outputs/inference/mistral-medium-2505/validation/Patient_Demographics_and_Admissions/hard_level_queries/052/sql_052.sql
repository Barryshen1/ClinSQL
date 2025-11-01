WITH
-- Get male patients aged 51-61
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 51 AND 61
),

-- Get index admissions meeting all criteria
index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS admission_seq
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    eligible_patients p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE
    a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM ADMIT'
    AND d.seq_num = 1  -- Principal diagnosis
    AND d.icd_code LIKE 'K85%'  -- Acute pancreatitis ICD-10 codes
    AND a.hospital_expire_flag = 0  -- Exclude patients who died during admission
),

-- Get only the first qualifying admission per patient
first_index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    los_days
  FROM
    index_admissions
  WHERE
    admission_seq = 1
),

-- Find readmissions within 30 days of discharge
readmissions AS (
  SELECT
    f.hadm_id AS index_hadm_id,
    a.hadm_id AS readmit_hadm_id,
    a.admittime AS readmit_admittime,
    TIMESTAMP_DIFF(a.admittime, f.dischtime, DAY) AS days_to_readmit
  FROM
    first_index_admissions f
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON f.subject_id = a.subject_id
  WHERE
    a.admittime > f.dischtime
    AND TIMESTAMP_DIFF(a.admittime, f.dischtime, DAY) <= 30
    AND a.hadm_id != f.hadm_id  -- Exclude same admission
),

-- Flag index admissions with readmissions
readmission_flags AS (
  SELECT
    f.hadm_id,
    f.los_days,
    CASE WHEN r.index_hadm_id IS NOT NULL THEN 1 ELSE 0 END AS had_readmission,
    CASE WHEN f.los_days > 9 THEN 1 ELSE 0 END AS long_stay
  FROM
    first_index_admissions f
  LEFT JOIN
    readmissions r ON f.hadm_id = r.index_hadm_id
)

-- Calculate statistics
SELECT
  -- 30-day readmission rate
  COUNT(CASE WHEN had_readmission = 1 THEN 1 END) * 100.0 /
    NULLIF(COUNT(*), 0) AS readmission_rate_percentage,

  -- Median LOS for readmitted vs non-readmitted
  APPROX_QUANTILES(CASE WHEN had_readmission = 1 THEN los_days END, 2)[OFFSET(1)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN had_readmission = 0 THEN los_days END, 2)[OFFSET(1)] AS median_los_non_readmitted,

  -- Percentage of stays >9 days
  COUNT(CASE WHEN had_readmission = 1 AND long_stay = 1 THEN 1 END) * 100.0 /
    NULLIF(COUNT(CASE WHEN had_readmission = 1 THEN 1 END), 0) AS pct_long_stay_readmitted,

  COUNT(CASE WHEN had_readmission = 0 AND long_stay = 1 THEN 1 END) * 100.0 /
    NULLIF(COUNT(CASE WHEN had_readmission = 0 THEN 1 END), 0) AS pct_long_stay_non_readmitted,

  -- Total counts for reference
  COUNT(*) AS total_index_admissions,
  COUNT(CASE WHEN had_readmission = 1 THEN 1 END) AS total_readmissions
FROM
  readmission_flags;