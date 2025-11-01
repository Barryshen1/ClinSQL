WITH uti_diag AS (
  -- diagnoses that indicate a urinary tract infection as the principal diagnosis
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    d.icd_version,
    dd.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    d.seq_num = 1 -- principal diagnosis
    AND (
      -- common ICD-9 codes
      (d.icd_version = 9 AND (
         d.icd_code LIKE '599.0'    -- UTI, site not specified
         OR d.icd_code LIKE '590%'  -- pyelonephritis / kidney infection
      ))
      OR
      -- common ICD-10 codes
      (d.icd_version = 10 AND (
         d.icd_code LIKE 'N39%'     -- UTI unspecified
         OR d.icd_code LIKE 'N10%'  -- acute pyelonephritis
         OR d.icd_code LIKE 'N30%'  -- cystitis etc.
      ))
      OR
      -- fallback text match on diagnosis description to capture variants
      (LOWER(COALESCE(dd.long_title, '')) LIKE '%urinary%'
       OR LOWER(COALESCE(dd.long_title, '')) LIKE '%cystitis%'
       OR LOWER(COALESCE(dd.long_title, '')) LIKE '%pyelonephr%')
    )
),
eligible_admissions AS (
  -- admissions that meet demographic and route/insurance filters AND have a principal UTI diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.insurance,
    p.gender,
    p.anchor_age,
    -- compute LOS in days as integer difference
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING (subject_id)
  JOIN
    uti_diag ud
  USING (subject_id, hadm_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND a.edregtime IS NOT NULL                  -- admitted via ED
    AND LOWER(COALESCE(a.insurance, '')) LIKE '%medicare%'
    AND a.hospital_expire_flag = 0               -- survived index admission
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
first_index_per_patient AS (
  -- choose the earliest eligible admission per subject as the index admission
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    los_days,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM
    eligible_admissions
),
index_cohort AS (
  SELECT
    subject_id,
    hadm_id AS index_hadm_id,
    admittime AS index_admittime,
    dischtime AS index_dischtime,
    los_days AS index_los_days
  FROM
    first_index_per_patient
  WHERE rn = 1
),
index_with_readmit AS (
  -- flag whether there is any all-cause readmission within 30 days after discharge
  SELECT
    ic.*,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = ic.subject_id
        AND a2.hadm_id <> ic.index_hadm_id
        AND a2.admittime > ic.index_dischtime
        AND a2.admittime <= TIMESTAMP_ADD(ic.index_dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmitted_30d
  FROM
    index_cohort ic
)
SELECT
  -- overall counts and 30-day readmission rate
  COUNT(*) AS n_index_admissions,
  SUM(readmitted_30d) AS n_readmitted_30d,
  ROUND(100.0 * SAFE_DIVIDE(SUM(readmitted_30d), COUNT(*)), 2) AS pct_readmitted_30d,
  -- median LOS and percent LOS>9 for readmitted
  -- APPROX_QUANTILES(..., 2)[OFFSET(1)] gives an approximate median
  APPROX_QUANTILES(IF(readmitted_30d = 1, index_los_days, NULL), 2)[OFFSET(1)] AS median_los_readmitted_days,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN readmitted_30d = 1 AND index_los_days > 9 THEN 1 ELSE 0 END), NULLIF(SUM(CASE WHEN readmitted_30d = 1 THEN 1 ELSE 0 END), 0)), 2) AS pct_los_gt9_readmitted,
  -- median LOS and percent LOS>9 for NOT readmitted
  APPROX_QUANTILES(IF(readmitted_30d = 0, index_los_days, NULL), 2)[OFFSET(1)] AS median_los_not_readmitted_days,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN readmitted_30d = 0 AND index_los_days > 9 THEN 1 ELSE 0 END), NULLIF(SUM(CASE WHEN readmitted_30d = 0 THEN 1 ELSE 0 END), 0)), 2) AS pct_los_gt9_not_readmitted
FROM
  index_with_readmit;