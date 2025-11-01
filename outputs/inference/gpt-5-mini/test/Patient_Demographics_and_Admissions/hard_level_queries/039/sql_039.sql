WITH index_adms AS (
  -- Select index admissions that meet cohort criteria
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- LOS in days (fractional)
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE), 1440.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
    AND diag.seq_num = 1  -- principal diagnosis
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code
    AND diag.icd_version = d.icd_version
  WHERE
    LOWER(p.gender) = 'm'
    AND p.anchor_age BETWEEN 65 AND 75
    AND LOWER(COALESCE(a.insurance, '')) LIKE '%medicare%'
    AND (
      LOWER(COALESCE(a.admission_location, '')) LIKE '%emergency%'
      OR LOWER(COALESCE(a.admission_type, '')) LIKE '%emergency%'
    )
    AND LOWER(COALESCE(d.long_title, '')) LIKE '%acute respiratory failure%'
    AND a.dischtime IS NOT NULL
),

readmitted_flag AS (
  -- Flag index admissions with any subsequent admission within 30 days
  SELECT
    ia.*,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = ia.subject_id
        AND a2.admittime > ia.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(ia.dischtime, INTERVAL 30 DAY)
    ) AS readmit30
  FROM index_adms ia
),

group_stats AS (
  -- Compute stats grouped by readmission status
  SELECT
    IF(readmit30, 'readmitted_within_30d', 'not_readmitted_within_30d') AS readmit_status,
    COUNT(*) AS n,
    SUM(IF(readmit30, 1, 0)) AS readmit_count,
    -- readmit_rate_pct here is readmit_count / n (will be 100% for the readmitted row and 0% for non-readmitted),
    -- it's mostly meaningful in the overall aggregate, but we compute for consistency
    100.0 * SAFE_DIVIDE(SUM(IF(readmit30, 1, 0)), COUNT(*)) AS readmit_rate_pct,
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
    100.0 * SAFE_DIVIDE(SUM(IF(los_days > 9, 1, 0)), COUNT(*)) AS pct_los_gt_9
  FROM readmitted_flag
  GROUP BY readmit_status
),

overall AS (
  -- Compute overall cohort-level stats
  SELECT
    'overall' AS readmit_status,
    COUNT(*) AS n,
    SUM(IF(readmit30, 1, 0)) AS readmit_count,
    100.0 * SAFE_DIVIDE(SUM(IF(readmit30, 1, 0)), COUNT(*)) AS readmit_rate_pct,
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
    100.0 * SAFE_DIVIDE(SUM(IF(los_days > 9, 1, 0)), COUNT(*)) AS pct_los_gt_9
  FROM readmitted_flag
)

-- Return overall followed by group-level rows
SELECT * FROM overall
UNION ALL
SELECT * FROM group_stats
ORDER BY
  CASE readmit_status
    WHEN 'overall' THEN 0
    WHEN 'readmitted_within_30d' THEN 1
    WHEN 'not_readmitted_within_30d' THEN 2
    ELSE 3
  END;