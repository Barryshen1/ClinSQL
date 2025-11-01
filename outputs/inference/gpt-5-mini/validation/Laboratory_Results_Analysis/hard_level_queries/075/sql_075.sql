WITH dvt_cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON a.hadm_id = dx.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dx.icd_code = dd.icd_code AND dx.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    -- ICD-10 I82* (venous embolism/thrombosis) or ICD-9 453* (phlebitis/thrombophlebitis)
    AND (
      (dx.icd_version = 10 AND SAFE_CAST(dx.icd_code AS STRING) LIKE 'I82%')
      OR (dx.icd_version = 9  AND SAFE_CAST(dx.icd_code AS STRING) LIKE '453%')
      OR LOWER(COALESCE(dd.long_title, '')) LIKE '%deep vein thrombosis%'
      OR LOWER(COALESCE(dd.long_title, '')) LIKE '%phlebitis%'
    )
),

-- 2) For cohort admissions: lab events in first 72 hours and mark "critical" events
cohort_labs_first72 AS (
  SELECT
    c.hadm_id,
    le.labevent_id,
    le.itemid,
    le.charttime,
    le.valuenum,
    le.ref_range_lower,
    le.ref_range_upper,
    le.flag,
    -- define criticality: flagged as abnormal/critical OR outside reference range when present
    (
      (LOWER(COALESCE(le.flag, '')) LIKE '%abnormal%')
      OR (LOWER(COALESCE(le.flag, '')) LIKE '%crit%')
      OR (le.valuenum IS NOT NULL AND le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
      OR (le.valuenum IS NOT NULL AND le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
    ) AS is_critical
  FROM dvt_cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
  WHERE le.charttime IS NOT NULL
    AND TIMESTAMP_DIFF(le.charttime, c.admittime, SECOND) BETWEEN 0 AND 72 * 3600
),

-- 3) Per-admission 72-hour instability score (count of critical lab events)
cohort_scores AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COALESCE(SUM(IF(cl.is_critical, 1, 0)), 0) AS critical_lab_count_72h
  FROM dvt_cohort c
  LEFT JOIN cohort_labs_first72 cl
    ON c.hadm_id = cl.hadm_id
  GROUP BY c.hadm_id, c.subject_id, c.admittime, c.dischtime, c.hospital_expire_flag
),

-- 4) Compute 95th percentile of the cohort instability score
cohort_p95 AS (
  SELECT
    APPROX_QUANTILES(critical_lab_count_72h, 100)[OFFSET(95)] AS p95_critical_count
  FROM cohort_scores
),

-- 5) Admissions in cohort at or above the 95th percentile
high_instability AS (
  SELECT
    cs.*
  FROM cohort_scores cs
  CROSS JOIN cohort_p95 p
  WHERE cs.critical_lab_count_72h >= p.p95_critical_count
),

-- 6) Summary metrics for high instability group
high_summary AS (
  SELECT
    COUNT(*) AS high_n_admissions,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS high_mortality_rate, -- proportion with in-hospital death
    AVG(TIMESTAMP_DIFF(dischtime, admittime, MINUTE) / 1440.0) AS high_mean_los_days,
    AVG(critical_lab_count_72h) AS high_mean_critical_labs_72h
  FROM high_instability
),

-- 7) For comparison: compute per-admission critical lab counts for all inpatients (all admissions)
all_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),

all_labs_first72 AS (
  SELECT
    a.hadm_id,
    le.labevent_id,
    le.itemid,
    le.charttime,
    le.valuenum,
    le.ref_range_lower,
    le.ref_range_upper,
    le.flag,
    (
      (LOWER(COALESCE(le.flag, '')) LIKE '%abnormal%')
      OR (LOWER(COALESCE(le.flag, '')) LIKE '%crit%')
      OR (le.valuenum IS NOT NULL AND le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
      OR (le.valuenum IS NOT NULL AND le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
    ) AS is_critical
  FROM all_admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.hadm_id = le.hadm_id
  WHERE le.charttime IS NOT NULL
    AND TIMESTAMP_DIFF(le.charttime, a.admittime, SECOND) BETWEEN 0 AND 72 * 3600
),

all_scores AS (
  SELECT
    a.hadm_id,
    COALESCE(SUM(IF(al.is_critical, 1, 0)), 0) AS critical_lab_count_72h
  FROM all_admissions a
  LEFT JOIN all_labs_first72 al
    ON a.hadm_id = al.hadm_id
  GROUP BY a.hadm_id
),

-- 8) Summary for all inpatients
all_summary AS (
  SELECT
    COUNT(*) AS all_n_admissions,
    AVG(critical_lab_count_72h) AS all_mean_critical_labs_72h
  FROM all_scores
)

-- Final: report percentile + high-group metrics + comparison to all inpatients
SELECT
  -- 95th percentile value for the cohort
  p.p95_critical_count AS cohort_95th_percentile_critical_lab_count_72h,

  -- Cohort size for reference
  (SELECT COUNT(*) FROM cohort_scores) AS cohort_n_admissions,

  -- High instability group metrics
  hs.high_n_admissions,
  hs.high_mortality_rate,
  hs.high_mean_los_days,
  hs.high_mean_critical_labs_72h,

  -- All inpatients metrics for comparison
  asu.all_n_admissions,
  asu.all_mean_critical_labs_72h AS all_mean_critical_labs_72h,

  -- Comparison: absolute difference and rate ratio (high / all)
  (hs.high_mean_critical_labs_72h - asu.all_mean_critical_labs_72h) AS absolute_difference_mean_critical_labs,
  SAFE_DIVIDE(hs.high_mean_critical_labs_72h, asu.all_mean_critical_labs_72h) AS rate_ratio_mean_critical_labs
FROM cohort_p95 p
CROSS JOIN high_summary hs
CROSS JOIN all_summary asu;