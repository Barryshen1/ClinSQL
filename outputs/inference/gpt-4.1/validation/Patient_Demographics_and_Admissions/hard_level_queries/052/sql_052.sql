WITH index_admissions AS (
  -- Step 1: Identify index admissions
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pat.anchor_age,
    pat.gender,
    adm.insurance,
    adm.admission_location,
    diag.icd_code,
    diag.icd_version,
    diag.seq_num
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 51 AND 61
    AND adm.insurance = 'Medicare'
    AND (
      LOWER(adm.admission_location) LIKE '%emergency%'
    )
    AND diag.seq_num = 1
    AND (
      -- Acute pancreatitis ICD-10: K85*, ICD-9: 577.0
      (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%')
      OR (diag.icd_version = 9 AND diag.icd_code = '5770')
    )
    AND adm.dischtime IS NOT NULL
    AND (adm.hospital_expire_flag = 0 OR adm.hospital_expire_flag IS NULL)
),

readmissions AS (
  -- Step 2: Find 30-day readmissions for each index admission
  SELECT
    idx.subject_id,
    idx.hadm_id AS index_hadm_id,
    idx.admittime AS index_admittime,
    idx.dischtime AS index_dischtime,
    MIN(next.admittime) AS readmit_admittime, -- first readmission within 30 days
    COUNT(next.hadm_id) AS num_readmissions_within_30d
  FROM
    index_admissions idx
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` next
      ON idx.subject_id = next.subject_id
      AND next.admittime > idx.dischtime
      AND next.admittime <= TIMESTAMP_ADD(idx.dischtime, INTERVAL 30 DAY)
  GROUP BY
    idx.subject_id, idx.hadm_id, idx.admittime, idx.dischtime
),

los_stats AS (
  -- Step 3: Calculate LOS and group by readmission status
  SELECT
    r.index_hadm_id,
    r.subject_id,
    r.index_admittime,
    r.index_dischtime,
    IF(r.num_readmissions_within_30d > 0, 1, 0) AS was_readmitted,
    TIMESTAMP_DIFF(r.index_dischtime, r.index_admittime, DAY) AS los_days
  FROM
    readmissions r
)

-- Step 4: Aggregate results
SELECT
  -- 30-day readmission rate
  ROUND(SUM(was_readmitted) / COUNT(*) * 100, 2) AS readmission_rate_percent,
  -- Median LOS for readmitted
  APPROX_QUANTILES(IF(was_readmitted=1, los_days, NULL), 2)[OFFSET(1)] AS median_los_readmitted,
  -- Median LOS for non-readmitted
  APPROX_QUANTILES(IF(was_readmitted=0, los_days, NULL), 2)[OFFSET(1)] AS median_los_nonreadmitted,
  -- Percent stays >9 days for readmitted
  ROUND(SUM(IF(was_readmitted=1 AND los_days > 9, 1, 0)) / NULLIF(SUM(IF(was_readmitted=1, 1, 0)),0) * 100, 2) AS percent_los_gt9_readmitted,
  -- Percent stays >9 days for non-readmitted
  ROUND(SUM(IF(was_readmitted=0 AND los_days > 9, 1, 0)) / NULLIF(SUM(IF(was_readmitted=0, 1, 0)),0) * 100, 2) AS percent_los_gt9_nonreadmitted
FROM
  los_stats
;