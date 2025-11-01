WITH principal_pancreatitis AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- fractional LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code
    AND d.icd_version = dicd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND LOWER(a.insurance) LIKE '%medicare%'
    -- admitted via ED (per admission_type or admission_location)
    AND (
      a.admission_type = 'EMERGENCY'
      OR LOWER(a.admission_location) LIKE '%emergency%'
      OR LOWER(a.admission_location) LIKE '%ed%'
    )
    -- principal diagnosis (seq_num = 1) is acute pancreatitis
    AND d.seq_num = 1
    AND LOWER(dicd.long_title) LIKE '%acute pancreatitis%'
),

-- Flag each index admission as readmitted within 30 days (exists any later admission within 30 days)
cohort_with_readmit AS (
  SELECT
    pp.*,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = pp.subject_id
        AND a2.admittime > pp.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(pp.dischtime, INTERVAL 30 DAY)
    ) AS readmitted_30d
  FROM principal_pancreatitis pp
)

-- Aggregate: median LOS and percent >9 days by readmission status, plus an overall summary row
SELECT
  readmit_status,
  n,
  median_los_days,
  pct_los_gt_9,
  readmit_rate_pct
FROM (
  -- per-group rows (readmitted vs not)
  SELECT
    IF(readmitted_30d, 'Readmitted within 30d', 'No readmission within 30d') AS readmit_status,
    COUNT(*) AS n,
    ROUND(APPROX_QUANTILES(los_days, 2)[OFFSET(1)], 2) AS median_los_days,
    ROUND(100.0 * SUM(CASE WHEN los_days > 9 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_los_gt_9,
    NULL AS readmit_rate_pct
  FROM cohort_with_readmit
  GROUP BY readmitted_30d

  UNION ALL

  -- overall summary row (one-line): overall readmission rate and cohort size,
  -- median LOS and pct >9 for entire cohort
  SELECT
    'Overall cohort' AS readmit_status,
    COUNT(*) AS n,
    ROUND(APPROX_QUANTILES(los_days, 2)[OFFSET(1)], 2) AS median_los_days,
    ROUND(100.0 * SUM(CASE WHEN los_days > 9 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_los_gt_9,
    ROUND(100.0 * SUM(CASE WHEN readmitted_30d THEN 1 ELSE 0 END) / COUNT(*), 2) AS readmit_rate_pct
  FROM cohort_with_readmit
)
ORDER BY
  -- place Overall last
  CASE WHEN readmit_status = 'Overall cohort' THEN 2 ELSE 1 END,
  readmit_status DESC;