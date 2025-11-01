WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND a.insurance = 'Medicare'
    AND LOWER(a.admission_location) IN (
      'transfer from hospital', 
      'transfer from other healthca', 
      'transfer from another hospital'
    )
    AND diag.seq_num = 1
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '410%')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I21%')
    )
    AND a.dischtime IS NOT NULL
),
index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    los_days,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM cohort
),
index_only AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    los_days
  FROM index_admissions
  WHERE rn = 1
),
readmission_flag AS (
  SELECT
    i.*,
    LEAD(i.admittime) OVER (PARTITION BY i.subject_id ORDER BY i.admittime) AS next_admittime,
    CASE
      WHEN LEAD(i.admittime) OVER (PARTITION BY i.subject_id ORDER BY i.admittime) <= DATETIME_ADD(i.dischtime, INTERVAL 30 DAY)
        THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM index_only i
),
summary_stats AS (
  SELECT
    readmitted_30d,
    los_days,
    CASE WHEN los_days > 4 THEN 1 ELSE 0 END AS los_gt_4_days
  FROM readmission_flag
)
SELECT
  -- 30-day readmission rate
  AVG(CAST(readmitted_30d AS FLOAT64)) AS readmission_rate_30d,
  -- Median index LOS for readmitted vs not
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 1 THEN los_days END, 100)[OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 0 THEN los_days END, 100)[OFFSET(50)] AS median_los_not_readmitted,
  -- Percent of index stays > 4 days
  AVG(CAST(los_gt_4_days AS FLOAT64)) AS pct_los_gt_4_days
FROM summary_stats;