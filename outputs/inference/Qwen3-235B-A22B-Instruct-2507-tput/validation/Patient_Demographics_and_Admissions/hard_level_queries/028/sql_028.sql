WITH index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60) AS los_days,
    -- Compute age at admission
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- Join to get diagnosis
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE
    p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 55 AND 65
    AND a.insurance = 'Medicare'
    AND LOWER(a.admission_location) LIKE '%emergency%'
    AND diag.seq_num = 1  -- Principal diagnosis
    AND LOWER(d_diag.long_title) LIKE '%cellulitis%'
),
-- Add next admission time for each patient
index_with_next AS (
  SELECT
    *,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM index_admissions
),
-- Flag readmission within 30 days
index_flags AS (
  SELECT
    *,
    CASE
      WHEN next_admittime IS NOT NULL
        AND DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30
        THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM index_with_next
)
-- Final aggregations
SELECT
  -- 30-day readmission rate
  AVG(readmitted_30d) AS readmission_rate_30d,
  -- Median index LOS for readmitted vs non-readmitted
  APPROX_QUANTILES(IF(readmitted_30d = 1, los_days, NULL), 2)[OFFSET(1)] AS median_los_readmitted,
  APPROX_QUANTILES(IF(readmitted_30d = 0, los_days, NULL), 2)[OFFSET(1)] AS median_los_non_readmitted,
  -- Percent of index stays >7 days
  AVG(CASE WHEN los_days > 7 THEN 1 ELSE 0 END) AS pct_los_gt_7_days
FROM index_flags;