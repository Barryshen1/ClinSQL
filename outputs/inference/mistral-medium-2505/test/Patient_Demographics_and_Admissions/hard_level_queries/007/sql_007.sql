WITH
-- Get male patients aged 83-93
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 83 AND 93
),

-- Get Medicare admissions via ED with principal diagnosis of TIA
tia_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.insurance,
    a.admission_location,
    d.icd_code,
    d.icd_version,
    d.long_title,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS admission_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM eligible_patients)
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM ADMIT'
    AND di.seq_num = 1  -- Principal diagnosis
    AND (d.long_title LIKE '%transient ischemic attack%' OR d.icd_code LIKE 'G45.%')
),

-- Get only the first admission for each patient (index admission)
index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    insurance,
    admission_location,
    icd_code,
    icd_version,
    long_title
  FROM
    tia_admissions
  WHERE
    admission_rank = 1
),

-- Calculate LOS for index admissions
index_admissions_with_los AS (
  SELECT
    *,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
  FROM
    index_admissions
),

-- Find readmissions within 30 days of index discharge
readmissions AS (
  SELECT
    ia.subject_id,
    ia.hadm_id AS index_hadm_id,
    a.hadm_id AS readmission_hadm_id,
    a.admittime AS readmission_admittime,
    TIMESTAMP_DIFF(a.admittime, ia.dischtime, DAY) AS days_to_readmission
  FROM
    index_admissions ia
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ia.subject_id = a.subject_id
    AND a.admittime > ia.dischtime
    AND TIMESTAMP_DIFF(a.admittime, ia.dischtime, DAY) <= 30
),

-- Flag patients with readmissions
readmission_flags AS (
  SELECT
    ia.subject_id,
    ia.hadm_id,
    ia.los_days,
    CASE WHEN r.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_readmission
  FROM
    index_admissions_with_los ia
  LEFT JOIN
    readmissions r
    ON ia.subject_id = r.subject_id
),

-- Calculate statistics
readmission_stats AS (
  SELECT
    COUNT(DISTINCT hadm_id) AS total_index_admissions,
    SUM(has_readmission) AS total_readmissions,
    ROUND(SUM(has_readmission) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS readmission_rate,
    PERCENTILE_CONT(CASE WHEN has_readmission = 1 THEN los_days ELSE NULL END, 0.5) AS median_los_readmitted,
    PERCENTILE_CONT(CASE WHEN has_readmission = 0 THEN los_days ELSE NULL END, 0.5) AS median_los_non_readmitted,
    ROUND(SUM(CASE WHEN los_days > 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS percent_stays_over_10_days
  FROM
    readmission_flags
)

SELECT * FROM readmission_stats;