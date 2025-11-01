WITH
-- Get male Medicare patients aged 76-86
eligible_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 76 AND 86
),

-- Get ED admissions with Medicare insurance
ed_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.insurance,
    a.hospital_expire_flag,
    a.deathtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    eligible_patients p ON a.subject_id = p.subject_id
  WHERE
    a.admission_location = 'EMERGENCY ROOM ADMIT'
    AND a.insurance = 'Medicare'
),

-- Get ischemic stroke diagnoses (principal diagnosis)
stroke_diagnoses AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.seq_num,
    d.icd_code,
    d.icd_version,
    di.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    d.seq_num = 1
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'I63.%')
      OR
      (d.icd_version = 9 AND d.icd_code IN ('433.01', '433.11', '433.21', '433.31', '433.81', '433.91', '434.01', '434.11', '434.91', '436'))
    )
),

-- Get index admissions (first qualifying admission per patient)
index_admissions AS (
  SELECT
    e.subject_id,
    e.hadm_id AS index_hadm_id,
    e.admittime AS index_admittime,
    e.dischtime AS index_dischtime,
    TIMESTAMP_DIFF(e.dischtime, e.admittime, DAY) AS index_los,
    e.hospital_expire_flag,
    e.deathtime,
    ROW_NUMBER() OVER (PARTITION BY e.subject_id ORDER BY e.admittime) AS admission_rank
  FROM
    ed_admissions e
  JOIN
    stroke_diagnoses s ON e.hadm_id = s.hadm_id
  WHERE
    e.hospital_expire_flag = 0
    AND (e.deathtime IS NULL OR e.deathtime > e.dischtime)
),

-- Get only the first admission per patient
first_index_admissions AS (
  SELECT
    subject_id,
    index_hadm_id,
    index_admittime,
    index_dischtime,
    index_los
  FROM
    index_admissions
  WHERE
    admission_rank = 1
),

-- Get all subsequent admissions within 30 days of discharge
readmissions AS (
  SELECT
    f.subject_id,
    f.index_hadm_id,
    a.hadm_id AS readmission_hadm_id,
    a.admittime AS readmission_admittime,
    TIMESTAMP_DIFF(a.admittime, f.index_dischtime, DAY) AS days_to_readmission
  FROM
    first_index_admissions f
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON f.subject_id = a.subject_id
  WHERE
    a.admittime > f.index_dischtime
    AND TIMESTAMP_DIFF(a.admittime, f.index_dischtime, DAY) <= 30
    AND a.hadm_id != f.index_hadm_id
),

-- Flag patients with readmissions
readmission_flags AS (
  SELECT
    f.subject_id,
    f.index_hadm_id,
    f.index_los,
    CASE WHEN r.subject_id IS NOT NULL THEN TRUE ELSE FALSE END AS has_readmission
  FROM
    first_index_admissions f
  LEFT JOIN
    readmissions r ON f.subject_id = r.subject_id
),

-- Calculate medians for readmitted and non-readmitted
median_los AS (
  SELECT
    APPROX_QUANTILES(IF(has_readmission, index_los, NULL), 100)[OFFSET(50)] AS median_los_readmitted,
    APPROX_QUANTILES(IF(NOT has_readmission, index_los, NULL), 100)[OFFSET(50)] AS median_los_non_readmitted
  FROM
    readmission_flags
)

-- Final calculations
SELECT
  -- 30-day all-cause readmission rate
  COUNT(CASE WHEN has_readmission THEN 1 END) * 100.0 / COUNT(*) AS readmission_rate,

  -- Median LOS for readmitted vs non-readmitted
  m.median_los_readmitted,
  m.median_los_non_readmitted,

  -- Percent of index stays >5 days
  COUNT(CASE WHEN index_los > 5 THEN 1 END) * 100.0 / COUNT(*) AS percent_stays_gt_5_days

FROM
  readmission_flags
CROSS JOIN
  median_los m;