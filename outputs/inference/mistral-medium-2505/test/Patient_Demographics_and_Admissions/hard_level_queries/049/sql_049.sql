WITH
-- Get female patients aged 61-71
female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 61 AND 71
),

-- Get Medicare patients admitted from SNF
medicare_snf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.insurance,
    a.hospital_expire_flag,
    -- Calculate LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN female_patients fp ON a.subject_id = fp.subject_id
  WHERE a.insurance = 'Medicare'
    AND a.admission_location = 'SNF'
    AND a.hospital_expire_flag = FALSE
),

-- Get principal diagnosis of acute kidney injury
aki_diagnoses AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.seq_num,
    d.icd_code,
    di.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE (d.icd_code LIKE 'N17.%' OR d.icd_code LIKE '584.%')
    AND d.seq_num = 1  -- Principal diagnosis
),

-- Combine admissions with AKI diagnosis
aki_admissions AS (
  SELECT
    msa.*,
    aki.icd_code,
    aki.long_title
  FROM medicare_snf_admissions msa
  JOIN aki_diagnoses aki ON msa.subject_id = aki.subject_id AND msa.hadm_id = aki.hadm_id
),

-- Identify index admissions (first admission for each patient)
index_admissions AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS admission_rank
  FROM aki_admissions
),

-- Get only index admissions
index_admissions_only AS (
  SELECT *
  FROM index_admissions
  WHERE admission_rank = 1
),

-- Find 30-day readmissions
readmissions AS (
  SELECT
    iao.subject_id,
    iao.hadm_id AS index_hadm_id,
    iao.admittime AS index_admittime,
    iao.dischtime AS index_dischtime,
    iao.los_days AS index_los,
    a.hadm_id AS readmit_hadm_id,
    a.admittime AS readmit_admittime,
    TIMESTAMP_DIFF(a.admittime, iao.dischtime, DAY) AS days_to_readmit
  FROM index_admissions_only iao
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON iao.subject_id = a.subject_id
  WHERE a.admittime > iao.dischtime
    AND TIMESTAMP_DIFF(a.admittime, iao.dischtime, DAY) <= 30
    AND a.hospital_expire_flag = FALSE
),

-- Flag patients with readmissions
readmission_flags AS (
  SELECT
    iao.subject_id,
    iao.hadm_id,
    iao.los_days,
    r.subject_id IS NOT NULL AS has_30day_readmission
  FROM index_admissions_only iao
  LEFT JOIN readmissions r ON iao.subject_id = r.subject_id AND iao.hadm_id = r.index_hadm_id
)

-- Final results
SELECT
  -- 30-day readmission rate
  ROUND(100 * SUM(CASE WHEN has_30day_readmission THEN 1 ELSE 0 END) / COUNT(*), 2) AS readmission_rate_pct,

  -- Median LOS for readmitted vs non-readmitted
  ROUND(PERCENTILE_CONT(CASE WHEN has_30day_readmission THEN los_days END, 0.5), 2) AS median_los_readmitted,
  ROUND(PERCENTILE_CONT(CASE WHEN NOT has_30day_readmission THEN los_days END, 0.5), 2) AS median_los_non_readmitted,

  -- Percent of index stays >6 days
  ROUND(100 * SUM(CASE WHEN los_days > 6 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_stays_gt_6days

FROM readmission_flags;