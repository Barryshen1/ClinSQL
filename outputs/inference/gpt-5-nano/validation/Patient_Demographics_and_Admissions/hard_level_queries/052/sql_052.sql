WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS index_los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  WHERE LOWER(a.admission_type) = 'emergency'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND di.seq_num = 1
    AND di.icd_code LIKE 'K85%'
    AND (a.hospital_expire_flag IS NULL OR a.hospital_expire_flag = 0)
    -- Medicare payer filter
    AND (a.insurance IS NOT NULL AND LOWER(a.insurance) LIKE '%medicare%')
),
index_with_read AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.index_los_days,
    MAX(CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS readmitted30
  FROM cohort AS c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
    ON a2.subject_id = c.subject_id
   AND a2.admittime >= c.dischtime
   AND a2.admittime < TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
   AND a2.hadm_id <> c.hadm_id
  GROUP BY
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.index_los_days
)
SELECT
  COUNT(*) AS total_index_admissions,
  SUM(readmitted30) AS total_readmissions,
  SAFE_DIVIDE(SUM(readmitted30), COUNT(*)) * 100 AS readmission_rate_percent,
  COALESCE((
    SELECT (APPROX_QUANTILES(index_los_days, 2))[OFFSET(1)]
    FROM index_with_read
    WHERE readmitted30 = 1
    LIMIT 1
  ), 0) AS median_los_readmitted_days,
  COALESCE((
    SELECT (APPROX_QUANTILES(index_los_days, 2))[OFFSET(1)]
    FROM index_with_read
    WHERE readmitted30 = 0
    LIMIT 1
  ), 0) AS median_los_nonreadmitted_days,
  SAFE_DIVIDE(SUM(CASE WHEN index_los_days > 9 THEN 1 ELSE 0 END), COUNT(*)) * 100 AS percent_stays_gt9_days
FROM index_with_read;