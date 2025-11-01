WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    p.anchor_age BETWEEN 60 AND 70
    AND p.gender = 'M'
    AND a.insurance = 'Medicare'
    AND a.admission_location LIKE '%EMERGENCY%'
    AND d.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%urinary tract infection%'
    AND a.hospital_expire_flag = 0
),

readmissions AS (
  SELECT
    c1.hadm_id AS index_hadm_id,
    c1.los AS index_los,
    MAX(CASE WHEN c2.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS is_readmitted
  FROM
    cohort c1
  LEFT JOIN
    cohort c2
  ON
    c1.subject_id = c2.subject_id
    AND c2.admittime > c1.dischtime
    AND c2.admittime <= DATETIME_ADD(c1.dischtime, INTERVAL 30 DAY)
    AND c2.hadm_id != c1.hadm_id
  GROUP BY
    c1.hadm_id, c1.los
),

readmit_stats AS (
  SELECT
    is_readmitted,
    COUNT(*) AS n,
    APPROX_QUANTILES(index_los, 2)[OFFSET(1)] AS median_los,
    AVG(CASE WHEN index_los > 9 THEN 1 ELSE 0 END) * 100 AS pct_los_gt_9
  FROM
    readmissions
  GROUP BY
    is_readmitted
)

SELECT
  SUM(CASE WHEN is_readmitted = 1 THEN n ELSE 0 END) / SUM(n) AS readmission_rate,
  MAX(CASE WHEN is_readmitted = 1 THEN median_los END) AS median_los_readmitted,
  MAX(CASE WHEN is_readmitted = 0 THEN median_los END) AS median_los_not_readmitted,
  MAX(CASE WHEN is_readmitted = 1 THEN pct_los_gt_9 END) AS pct_los_gt_9_readmitted,
  MAX(CASE WHEN is_readmitted = 0 THEN pct_los_gt_9 END) AS pct_los_gt_9_not_readmitted
FROM
  readmit_stats;