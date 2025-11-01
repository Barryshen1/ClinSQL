WITH cohort AS (
  -- index admissions meeting inclusion criteria
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.insurance,
    a.admission_location,
    p.gender,
    p.anchor_age,
    -- LOS in days (fractional)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE) / 1440.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING(subject_id)
  WHERE
    lower(p.gender) = 'm'
    AND p.anchor_age BETWEEN 68 AND 78
    AND lower(a.insurance) LIKE '%medicare%'
    -- admitted from SNF / skilled nursing; use several common substrings
    AND (
      lower(a.admission_location) LIKE '%snf%'
      OR lower(a.admission_location) LIKE '%skilled%'
      OR lower(a.admission_location) LIKE '%nurs%'
      OR lower(a.admission_location) LIKE '%nursing%'
    )
    -- principal diagnosis (seq_num = 1) is a UTI-related diagnosis (by description text)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE
        d.hadm_id = a.hadm_id
        AND d.seq_num = 1
        AND (
          lower(dd.long_title) LIKE '%urinary tract%'
          OR lower(dd.long_title) LIKE '%cystitis%'
          OR lower(dd.long_title) LIKE '%pyelonephrit%'
          OR lower(dd.long_title) LIKE '%uti%'
        )
    )
),

with_readmit AS (
  -- mark whether each index admission has any readmission within 30 days
  SELECT
    c.*,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = c.subject_id
        AND a2.admittime > c.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
    ) AS readmitted_30
  FROM cohort c
)

-- 1) Grouped metrics (readmitted vs not) and 2) overall 30-day readmission rate
SELECT
  IF(readmitted_30, 'readmitted_30d', 'not_readmitted_30d') AS readmission_group,
  COUNT(*) AS n_index_admissions,
  -- overall readmission rate column only meaningful for the overall row; NULL here
  NULL AS overall_readmit_30d_pct,
  -- median LOS (days) in each group
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
  -- percent of stays > 6 days in each group
  ROUND(100.0 * SUM(CASE WHEN los_days > 6 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_los_gt_6_days
FROM with_readmit
GROUP BY readmitted_30

UNION ALL

SELECT
  'overall_30d_readmit_rate' AS readmission_group,
  COUNT(*) AS n_index_admissions,
  -- overall 30-day readmission rate (percent)
  ROUND(100.0 * SUM(CASE WHEN readmitted_30 THEN 1 ELSE 0 END) / COUNT(*), 2) AS overall_readmit_30d_pct,
  NULL AS median_los_days,
  NULL AS pct_los_gt_6_days
FROM with_readmit
ORDER BY readmission_group DESC;