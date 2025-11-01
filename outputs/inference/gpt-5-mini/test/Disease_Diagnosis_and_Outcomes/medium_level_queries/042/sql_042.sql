WITH
-- Cohort: male patients age 69-79 whose primary diagnosis is a myocardial infarction (AMI),
-- excluding admissions with any diagnosis indicating shock or respiratory failure.
ami_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- primary diagnosis = seq_num = 1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_primary
    ON a.hadm_id = d_primary.hadm_id AND d_primary.seq_num = 1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd_primary
    ON d_primary.icd_code = dd_primary.icd_code
       AND d_primary.icd_version = dd_primary.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 69 AND 79
    AND LOWER(dd_primary.long_title) LIKE '%myocardial infarction%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- Exclude admissions with any diagnosis of shock or respiratory failure
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_any
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd_any
        ON d_any.icd_code = dd_any.icd_code
           AND d_any.icd_version = dd_any.icd_version
      WHERE d_any.hadm_id = a.hadm_id
        AND (
          LOWER(dd_any.long_title) LIKE '%shock%'
          OR LOWER(dd_any.long_title) LIKE '%respiratory failure%'
        )
    )
),

-- Add LOS bin
cohort AS (
  SELECT
    *,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE '8+'
    END AS los_bin
  FROM ami_admissions
),

-- Aggregate summary per LOS bin
summary AS (
  SELECT
    los_bin,
    COUNT(*) AS n_admissions,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
    ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_pct,
    -- approximate median LOS using 100 quantiles and taking the 50th percentile
    CAST(APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS INT64) AS median_los_days
  FROM cohort
  GROUP BY los_bin
),

-- Discharge destination counts per los_bin
dest_raw AS (
  SELECT
    los_bin,
    COALESCE(discharge_location, 'UNKNOWN') AS discharge_location,
    COUNT(*) AS cnt
  FROM cohort
  GROUP BY los_bin, discharge_location
),

-- Add total counts per los_bin (analytic function used here but not inside an aggregate)
dest_with_totals AS (
  SELECT
    dr.*,
    SUM(dr.cnt) OVER (PARTITION BY dr.los_bin) AS total_cnt
  FROM dest_raw dr
),

-- Build destination summary strings per los_bin
dest_summary AS (
  SELECT
    los_bin,
    STRING_AGG(
      CONCAT(
        discharge_location, ': ', CAST(cnt AS STRING), ' (',
        CAST(ROUND(100.0 * cnt / total_cnt, 1) AS STRING),
        '%)'
      ), '; ' ORDER BY cnt DESC
    ) AS dest_summary
  FROM dest_with_totals
  GROUP BY los_bin
)

SELECT
  s.los_bin,
  s.n_admissions,
  s.deaths,
  s.mortality_pct,
  s.median_los_days,
  COALESCE(ds.dest_summary, 'none recorded') AS discharge_destinations
FROM
  summary s
LEFT JOIN
  dest_summary ds
ON s.los_bin = ds.los_bin
ORDER BY
  CASE s.los_bin WHEN '1-3' THEN 1 WHEN '4-7' THEN 2 WHEN '8+' THEN 3 ELSE 4 END;