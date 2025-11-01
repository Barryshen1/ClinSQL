WITH cohort AS (
  -- Identify index admissions
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_location,
    a.insurance,
    p.gender,
    p.anchor_age,
    d.icd_code,
    d.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 61 AND 71
    AND LOWER(a.insurance) LIKE '%medicare%'
    AND LOWER(a.admission_location) LIKE '%snf%'
    AND d.seq_num = 1
    AND (
      (d.icd_version = 10 AND LEFT(d.icd_code, 3) = 'N17')
      OR
      (d.icd_version = 9 AND LEFT(d.icd_code, 3) = '584')
    )
    AND (a.hospital_expire_flag = 0 OR a.hospital_expire_flag IS NULL)
    AND (a.deathtime IS NULL OR a.deathtime > a.dischtime)
),

readmissions AS (
  -- For each index admission, find first readmission within 30 days
  SELECT
    c.subject_id,
    c.hadm_id AS index_hadm_id,
    c.admittime AS index_admittime,
    c.dischtime AS index_dischtime,
    MIN(a2.admittime) AS readmit_admittime,
    MIN(a2.hadm_id) AS readmit_hadm_id
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
      ON c.subject_id = a2.subject_id
      AND a2.admittime > c.dischtime
      AND a2.admittime <= DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)
  GROUP BY
    c.subject_id, c.hadm_id, c.admittime, c.dischtime
),

cohort_with_readmit AS (
  -- Merge cohort and readmission info
  SELECT
    c.*,
    r.readmit_hadm_id,
    r.readmit_admittime,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los,
    CASE WHEN r.readmit_hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted_30d
  FROM
    cohort c
    LEFT JOIN readmissions r
      ON c.subject_id = r.subject_id
      AND c.hadm_id = r.index_hadm_id
)

-- Final aggregation
SELECT
  COUNT(*) AS n_index_admissions,
  ROUND(SUM(readmitted_30d) / COUNT(*) * 100, 2) AS readmission_rate_30d_percent,
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los_all,
  APPROX_QUANTILES(IF(readmitted_30d = 1, los, NULL), 2)[OFFSET(1)] AS median_los_readmitted,
  APPROX_QUANTILES(IF(readmitted_30d = 0, los, NULL), 2)[OFFSET(1)] AS median_los_nonreadmitted,
  ROUND(SUM(CASE WHEN los > 6 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS percent_los_gt_6_days
FROM
  cohort_with_readmit;