WITH cohort AS (
  -- Step 1: Identify index admissions
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.admission_location,
    adm.insurance,
    adm.hospital_expire_flag,
    pat.gender,
    pat.anchor_age,
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
    AND pat.anchor_age BETWEEN 65 AND 75
    AND adm.insurance LIKE '%Medicare%'
    AND (
      adm.admission_location LIKE '%EMERGENCY%'
      OR adm.admission_location LIKE '%ED%'
      OR adm.admission_location LIKE '%EMER%'
    )
    AND diag.seq_num = 1
    AND (
      -- ICD-10 J96.x or ICD-9 518.81, 518.82, 518.84
      (diag.icd_version = 10 AND diag.icd_code LIKE 'J96%')
      OR (diag.icd_version = 9 AND diag.icd_code IN ('51881', '51882', '51884'))
    )
    AND adm.hospital_expire_flag = 0
    AND adm.deathtime IS NULL
),
readmissions AS (
  -- Step 2: Find 30-day readmissions for each index admission
  SELECT
    c.subject_id,
    c.hadm_id AS index_hadm_id,
    c.admittime AS index_admittime,
    c.dischtime AS index_dischtime,
    MIN(a.admittime) AS readmit_admittime,
    MIN(a.hadm_id) AS readmit_hadm_id
  FROM
    cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON c.subject_id = a.subject_id
      AND a.admittime > c.dischtime
      AND a.admittime <= DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)
  GROUP BY
    c.subject_id, c.hadm_id, c.admittime, c.dischtime
),
index_with_readmit_flag AS (
  -- Step 3: Mark index admissions as readmitted or not
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los,
    CASE WHEN r.readmit_hadm_id IS NOT NULL THEN 1 ELSE 0 END AS was_readmitted
  FROM
    cohort c
    LEFT JOIN readmissions r
      ON c.subject_id = r.subject_id
      AND c.hadm_id = r.index_hadm_id
)
-- Step 4: Aggregate results
SELECT
  COUNT(*) AS total_index_admissions,
  SUM(was_readmitted) AS num_readmitted,
  ROUND(SAFE_DIVIDE(SUM(was_readmitted), COUNT(*)), 4) AS readmission_rate,
  -- Median LOS for readmitted
  APPROX_QUANTILES(IF(was_readmitted=1, los, NULL), 2)[OFFSET(1)] AS median_los_readmitted,
  -- Median LOS for non-readmitted
  APPROX_QUANTILES(IF(was_readmitted=0, los, NULL), 2)[OFFSET(1)] AS median_los_nonreadmitted,
  -- Percent LOS > 9 days for readmitted
  ROUND(SAFE_DIVIDE(SUM(CASE WHEN was_readmitted=1 AND los > 9 THEN 1 ELSE 0 END), NULLIF(SUM(was_readmitted),0)), 4) AS pct_los_gt9_readmitted,
  -- Percent LOS > 9 days for non-readmitted
  ROUND(SAFE_DIVIDE(SUM(CASE WHEN was_readmitted=0 AND los > 9 THEN 1 ELSE 0 END), NULLIF(SUM(CASE WHEN was_readmitted=0 THEN 1 ELSE 0 END),0)), 4) AS pct_los_gt9_nonreadmitted
FROM
  index_with_readmit_flag;