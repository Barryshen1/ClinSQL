WITH
-- 1) Female, age 38-48 admissions (hospital admissions)
female_age_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING (subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND a.hadm_id IS NOT NULL
),

-- 2) Identify AMI admissions (ICD-9 410* or ICD-10 I21* or text mentions acute myocardial infarction)
ami_hadms AS (
  SELECT DISTINCT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    LOWER(COALESCE(dd.long_title, '')) LIKE '%acute myocardial%'
    OR SAFE_CAST(d.icd_code AS STRING) LIKE 'I21%'  -- ICD-10 AMI
    OR SAFE_CAST(d.icd_code AS STRING) LIKE '410%'  -- ICD-9 AMI
),

-- 3) Lab events in the first 72 hours for the cohort and a flag for "critical" per event
labs_first_72h AS (
  SELECT
    fa.hadm_id,
    le.subject_id,
    le.itemid,
    le.charttime,
    le.valuenum,
    le.value,
    le.ref_range_lower,
    le.ref_range_upper,
    le.flag,
    -- define critical using numeric range when available, otherwise textual flag
    (
      (le.valuenum IS NOT NULL AND (
         (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
         OR
         (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
       ))
      OR
      (le.flag IS NOT NULL AND (
         LOWER(le.flag) LIKE '%abnorm%' OR LOWER(le.flag) LIKE '%low%' OR LOWER(le.flag) LIKE '%high%' OR LOWER(le.flag) LIKE '%crit%'
       ))
    ) AS is_critical
  FROM
    female_age_admissions fa
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON le.hadm_id = fa.hadm_id
  WHERE
    le.charttime IS NOT NULL
    AND le.charttime BETWEEN fa.admittime AND TIMESTAMP_ADD(fa.admittime, INTERVAL 72 HOUR)
),

-- 4) Per-admission instability score = count of critical lab events in first 72h
instability_by_hadm AS (
  SELECT
    fa.hadm_id,
    fa.subject_id,
    fa.admittime,
    fa.dischtime,
    fa.hospital_expire_flag,
    COALESCE(SUM(IF(l.is_critical, 1, 0)), 0) AS instability_score,
    -- LOS in days (fractional)
    SAFE_DIVIDE(TIMESTAMP_DIFF(fa.dischtime, fa.admittime, SECOND), 86400.0) AS los_days
  FROM
    female_age_admissions fa
    LEFT JOIN labs_first_72h l
      USING (hadm_id)
  GROUP BY
    fa.hadm_id, fa.subject_id, fa.admittime, fa.dischtime, fa.hospital_expire_flag
),

-- 5) AMI admissions with instability scores
ami_instability AS (
  SELECT
    ib.*,
    1 AS is_ami
  FROM
    instability_by_hadm ib
    JOIN ami_hadms a
      USING (hadm_id)
),

-- 6) Control admissions (female age-matched without AMI)
control_instability AS (
  SELECT
    ib.*,
    0 AS is_ami
  FROM
    instability_by_hadm ib
    LEFT JOIN ami_hadms a
      USING (hadm_id)
  WHERE
    a.hadm_id IS NULL
),

-- 7) Combine AMI records and assign quartiles among AMI only
ami_quartiles AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    instability_score,
    los_days,
    NTILE(4) OVER (ORDER BY instability_score ASC) AS instability_quartile
  FROM
    ami_instability
),

-- 8) Summary stats by quartile for AMI admissions
ami_quartile_summary AS (
  SELECT
    instability_quartile,
    COUNT(*) AS n_admissions,
    ROUND(AVG(instability_score), 2) AS mean_instability,
    -- mean and median LOS
    ROUND(AVG(los_days), 2) AS mean_los_days,
    ROUND(APPROX_QUANTILES(los_days, 2)[OFFSET(1)], 2) AS median_los_days,
    ROUND(AVG(IF(hospital_expire_flag = 1, 1.0, 0.0)), 3) AS in_hospital_mortality_rate
  FROM
    ami_quartiles
  GROUP BY
    instability_quartile
  ORDER BY
    instability_quartile
),

-- 9) Overall critical-lab rates (any critical lab within 72h) for AMI vs controls
critical_rates AS (
  SELECT
    'AMI' AS group_label,
    COUNT(*) AS n_admissions,
    SUM(IF(instability_score > 0, 1, 0)) AS n_with_critical,
    ROUND(100.0 * SAFE_DIVIDE(SUM(IF(instability_score > 0, 1, 0)), COUNT(*)), 2) AS pct_with_critical
  FROM
    ami_instability

  UNION ALL

  SELECT
    'Age-matched controls (no AMI)' AS group_label,
    COUNT(*) AS n_admissions,
    SUM(IF(instability_score > 0, 1, 0)) AS n_with_critical,
    ROUND(100.0 * SAFE_DIVIDE(SUM(IF(instability_score > 0, 1, 0)), COUNT(*)), 2) AS pct_with_critical
  FROM
    control_instability
)

-- Final outputs: quartile summary for AMI and critical rate comparison
SELECT
  'AMI quartile summary' AS report_section,
  CAST(NULL AS STRING) AS group_label,
  CAST(NULL AS INT64) AS n_admissions,
  CAST(NULL AS FLOAT64) AS mean_instability,
  CAST(NULL AS FLOAT64) AS mean_los_days,
  CAST(NULL AS FLOAT64) AS median_los_days,
  CAST(NULL AS FLOAT64) AS in_hospital_mortality_rate
UNION ALL
SELECT
  'AMI quartile summary',
  'Quartile ' || CAST(instability_quartile AS STRING),
  n_admissions,
  mean_instability,
  mean_los_days,
  median_los_days,
  in_hospital_mortality_rate
FROM
  ami_quartile_summary
UNION ALL
SELECT
  'Critical-lab rates (72h)',
  group_label,
  n_admissions,
  CAST(n_with_critical AS FLOAT64),
  pct_with_critical,
  CAST(NULL AS FLOAT64),
  CAST(NULL AS FLOAT64)
FROM
  critical_rates
ORDER BY
  report_section, group_label;