WITH index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    LEAD(a.admittime) OVER (
      PARTITION BY a.subject_id
      ORDER BY a.admittime
    ) AS next_admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.subject_id = d.subject_id
      AND a.hadm_id = d.hadm_id
      AND d.seq_num = 1
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND a.insurance = 'MEDICARE'
    AND a.admission_location = 'EMERGENCY'
    AND (
      (d.icd_version = 9 AND d.icd_code = '5990')
      OR (d.icd_version = 10 AND d.icd_code = 'N39.0')
    )
),
flagged AS (
  SELECT
    subject_id,
    hadm_id,
    los_days,
    CASE
      WHEN next_admittime IS NOT NULL
       AND TIMESTAMP_DIFF(next_admittime, dischtime, DAY) BETWEEN 1 AND 30
      THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM
    index_admissions
),
summary AS (
  SELECT
    COUNT(*) AS total_idx,
    SUM(readmitted_30d) AS num_readmit,
    -- Readmission rate
    SAFE_DIVIDE(SUM(readmitted_30d), COUNT(*)) AS readmit_rate,
    -- Median LOS for readmitted
    APPROX_QUANTILES(
      CASE WHEN readmitted_30d = 1 THEN los_days ELSE NULL END, 2
    )[OFFSET(1)] AS median_los_readmit,
    -- Median LOS for non-readmitted
    APPROX_QUANTILES(
      CASE WHEN readmitted_30d = 0 THEN los_days ELSE NULL END, 2
    )[OFFSET(1)] AS median_los_nonreadmit,
    -- Percent with LOS > 9 in readmitted
    SAFE_DIVIDE(
      SUM(CASE WHEN readmitted_30d = 1 AND los_days > 9 THEN 1 ELSE 0 END),
      SUM(CASE WHEN readmitted_30d = 1 THEN 1 ELSE 0 END)
    ) AS pct_los_gt9_readmit,
    -- Percent with LOS > 9 in non-readmitted
    SAFE_DIVIDE(
      SUM(CASE WHEN readmitted_30d = 0 AND los_days > 9 THEN 1 ELSE 0 END),
      SUM(CASE WHEN readmitted_30d = 0 THEN 1 ELSE 0 END)
    ) AS pct_los_gt9_nonreadmit
  FROM
    flagged
)
SELECT
  total_idx,
  num_readmit,
  ROUND(readmit_rate * 100, 2) AS readmission_rate_pct,
  median_los_readmit,
  median_los_nonreadmit,
  ROUND(pct_los_gt9_readmit * 100, 2) AS pct_los_gt9_readmit,
  ROUND(pct_los_gt9_nonreadmit * 100, 2) AS pct_los_gt9_nonreadmit
FROM
  summary;