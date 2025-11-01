WITH
-- Get female Medicare patients aged 68-78
eligible_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 68 AND 78
),

-- Get their ED admissions with Medicare insurance
ed_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.insurance,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    eligible_patients p ON a.subject_id = p.subject_id
  WHERE
    a.admission_location = 'EMERGENCY ROOM ADMIT'
    AND a.insurance = 'Medicare'
    AND a.hospital_expire_flag = 0
),

-- Get principal diagnosis of hemorrhagic stroke
stroke_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.los_days
  FROM
    ed_admissions a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE
    d.seq_num = 1
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'I61.%')
      OR (d.icd_version = 9 AND d.icd_code LIKE '431.%')
    )
),

-- For each patient, get their first qualifying admission as index admission
index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    los_days,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS admission_rank
  FROM
    stroke_admissions
),

-- Get only the first admission per patient
first_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    los_days
  FROM
    index_admissions
  WHERE
    admission_rank = 1
),

-- Find 30-day readmissions (from any admission location)
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
  FROM
    first_admissions f
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON f.subject_id = a.subject_id
  WHERE
    a.hadm_id != f.hadm_id
    AND a.admittime > f.dischtime
    AND TIMESTAMP_DIFF(a.admittime, f.dischtime, DAY) <= 30
),

-- Flag patients with readmissions
readmission_flags AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.los_days,
    CASE WHEN r.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_readmission
  FROM
    first_admissions f
  LEFT JOIN
    readmissions r ON f.subject_id = r.subject_id
),

-- Count total patients to check if we have any
patient_counts AS (
  SELECT
    COUNT(*) AS total_patients,
    COUNT(CASE WHEN has_readmission = 1 THEN 1 END) AS readmitted_patients,
    COUNT(CASE WHEN los_days > 4 THEN 1 END) AS los_gt_4_patients
  FROM
    readmission_flags
)

-- Calculate final metrics with NULL handling
SELECT
  -- 30-day readmission rate
  CASE
    WHEN total_patients = 0 THEN NULL
    ELSE readmitted_patients / total_patients
  END AS readmission_rate,

  -- Median LOS for readmitted vs non-readmitted
  APPROX_QUANTILES(CASE WHEN has_readmission = 1 THEN los_days END, 2)[OFFSET(1)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN has_readmission = 0 THEN los_days END, 2)[OFFSET(1)] AS median_los_non_readmitted,

  -- % with LOS >4 days
  CASE
    WHEN total_patients = 0 THEN NULL
    ELSE los_gt_4_patients / total_patients
  END AS percent_los_gt_4_days,

  -- Include counts for transparency
  total_patients,
  readmitted_patients,
  los_gt_4_patients

FROM
  readmission_flags
CROSS JOIN
  patient_counts
LIMIT 1;