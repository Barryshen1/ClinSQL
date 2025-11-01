WITH
-- Get male Medicare patients aged 65-75
eligible_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 65 AND 75
),

-- Get their admissions from ED with Medicare
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
),

-- Get principal diagnosis of acute respiratory failure
arf_diagnoses AS (
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
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    (d.icd_code = '518.81' AND d.icd_version = 9) OR
    (d.icd_code = 'J96.00' AND d.icd_version = 10)
    AND d.seq_num = 1  -- Principal diagnosis
),

-- Combine to get index admissions
index_admissions AS (
  SELECT
    ea.subject_id,
    ea.hadm_id,
    ea.admittime,
    ea.dischtime,
    ea.los_days,
    ea.hospital_expire_flag,
    arf.long_title AS principal_diagnosis
  FROM
    ed_admissions ea
  JOIN
    arf_diagnoses arf ON ea.subject_id = arf.subject_id AND ea.hadm_id = arf.hadm_id
),

-- Get all subsequent admissions within 30 days for each patient
readmissions AS (
  SELECT
    ia.subject_id,
    ia.hadm_id AS index_hadm_id,
    ia.admittime AS index_admittime,
    ia.dischtime AS index_dischtime,
    ia.los_days AS index_los,
    a.hadm_id AS readmit_hadm_id,
    a.admittime AS readmit_admittime,
    TIMESTAMP_DIFF(a.admittime, ia.dischtime, DAY) AS days_to_readmit
  FROM
    index_admissions ia
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ia.subject_id = a.subject_id
  WHERE
    a.admittime > ia.dischtime
    AND TIMESTAMP_DIFF(a.admittime, ia.dischtime, DAY) <= 30
    AND a.hadm_id != ia.hadm_id
),

-- Flag patients with readmissions
readmission_flags AS (
  SELECT
    ia.subject_id,
    ia.hadm_id,
    ia.los_days,
    ia.hospital_expire_flag,
    CASE WHEN r.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_readmission
  FROM
    index_admissions ia
  LEFT JOIN
    readmissions r ON ia.subject_id = r.subject_id AND ia.hadm_id = r.index_hadm_id
),

-- Calculate statistics
readmission_stats AS (
  SELECT
    COUNT(*) AS total_index_admissions,
    SUM(has_readmission) AS readmitted_count,
    ROUND(SUM(has_readmission) * 100.0 / COUNT(*), 2) AS readmission_rate,
    ROUND(AVG(CASE WHEN has_readmission = 1 THEN los_days ELSE NULL END), 2) AS avg_los_readmitted,
    ROUND(AVG(CASE WHEN has_readmission = 0 THEN los_days ELSE NULL END), 2) AS avg_los_not_readmitted,
    ROUND(PERCENTILE_CONT(CASE WHEN has_readmission = 1 THEN los_days ELSE NULL END, 0.5), 2) AS median_los_readmitted,
    ROUND(PERCENTILE_CONT(CASE WHEN has_readmission = 0 THEN los_days ELSE NULL END, 0.5), 2) AS median_los_not_readmitted,
    ROUND(SUM(CASE WHEN has_readmission = 1 AND los_days > 9 THEN 1 ELSE 0 END) * 100.0 /
          NULLIF(SUM(CASE WHEN has_readmission = 1 THEN 1 ELSE 0 END), 0), 2) AS pct_los_gt9_readmitted,
    ROUND(SUM(CASE WHEN has_readmission = 0 AND los_days > 9 THEN 1 ELSE 0 END) * 100.0 /
          NULLIF(SUM(CASE WHEN has_readmission = 0 THEN 1 ELSE 0 END), 0), 2) AS pct_los_gt9_not_readmitted
  FROM
    readmission_flags
)

SELECT * FROM readmission_stats;