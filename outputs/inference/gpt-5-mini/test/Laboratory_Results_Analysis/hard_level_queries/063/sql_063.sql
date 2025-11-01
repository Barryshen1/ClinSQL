WITH
-- Short aliases for datasets
admissions AS (
  SELECT * FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
patients AS (
  SELECT * FROM `physionet-data.mimiciv_3_1_hosp.patients`
),
diagnoses_icd AS (
  SELECT * FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
),
d_icd_diagnoses AS (
  SELECT * FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
),
labevents AS (
  SELECT * FROM `physionet-data.mimiciv_3_1_hosp.labevents`
),

-- 1) Admissions with pulmonary embolism in female patients age 53-63
pe_admissions AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM admissions a
  JOIN patients p
    ON a.subject_id = p.subject_id
  JOIN diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  JOIN d_icd_diagnoses dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND LOWER(dd.long_title) LIKE '%pulmonary embol%'
),

-- 2) Per-admission 72-hour lab aggregates for the PE cohort
cohort_hadm_scores AS (
  SELECT
    h.hadm_id,
    h.subject_id,
    h.hospital_expire_flag,
    h.admittime,
    h.dischtime,
    -- fractional days LOS
    CASE
      WHEN h.dischtime IS NOT NULL AND h.admittime IS NOT NULL
      THEN TIMESTAMP_DIFF(h.dischtime, h.admittime, SECOND) / 86400.0
      ELSE NULL
    END AS los_days,
    -- instability score: count of critical lab events in first 72 hours
    COALESCE(SUM(
      CASE
        WHEN (
          -- flagged abnormal/critical (conservative set)
          COALESCE(le.flag, '') != '' AND LOWER(TRIM(le.flag)) IN ('abnormal','high','low','crit','critical','ab')
        ) THEN 1
        WHEN (
          -- numeric value outside reference range when ref ranges are present
          le.valuenum IS NOT NULL
          AND (
            (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
            OR
            (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
          )
        ) THEN 1
        ELSE 0
      END
    ), 0) AS instability_score,
    -- total lab events considered (valuenum present OR non-empty flag)
    COALESCE(SUM(
      CASE WHEN (le.valuenum IS NOT NULL OR COALESCE(le.flag,'') != '') THEN 1 ELSE 0 END
    ), 0) AS total_labs,
    -- total critical events counted (for later aggregation convenience)
    COALESCE(SUM(
      CASE
        WHEN (
          COALESCE(le.flag, '') != '' AND LOWER(TRIM(le.flag)) IN ('abnormal','high','low','crit','critical','ab')
        ) THEN 1
        WHEN (
          le.valuenum IS NOT NULL
          AND (
            (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
            OR
            (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
          )
        ) THEN 1
        ELSE 0
      END
    ), 0) AS total_critical_events
  FROM pe_admissions h
  LEFT JOIN labevents le
    ON le.hadm_id = h.hadm_id
   AND le.charttime BETWEEN h.admittime AND TIMESTAMP_ADD(h.admittime, INTERVAL 72 HOUR)
  GROUP BY h.hadm_id, h.subject_id, h.hospital_expire_flag, h.admittime, h.dischtime
),

-- 3) Compute 75th percentile threshold of instability_score in the cohort
threshold_val AS (
  SELECT
    (APPROX_QUANTILES(instability_score, 100))[OFFSET(75)] AS instability_75pct
  FROM cohort_hadm_scores
),

-- 4) Metrics for cohort admissions with instability_score >= threshold
cohort_selected_metrics AS (
  SELECT
    t.instability_75pct AS threshold,
    COUNT(1) AS n_admissions,
    100.0 * SUM(CASE WHEN ch.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(1), 0) AS mortality_pct,
    AVG(ch.los_days) AS mean_los_days,
    -- cohort critical lab rate across these admissions: sum(critical events) / sum(total labs)
    SAFE_DIVIDE(SUM(ch.total_critical_events), NULLIF(SUM(ch.total_labs), 0)) AS cohort_critical_rate,
    SUM(ch.total_critical_events) AS cohort_total_critical_events,
    SUM(ch.total_labs) AS cohort_total_labs
  FROM cohort_hadm_scores ch
  CROSS JOIN threshold_val t
  WHERE ch.instability_score >= t.instability_75pct
  GROUP BY t.instability_75pct
),

-- 5) Baseline: per-admission 72-hour lab aggregates for all inpatients
inpatient_hadm_scores AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.hospital_expire_flag,
    a.admittime,
    a.dischtime,
    COALESCE(SUM(
      CASE
        WHEN (
          COALESCE(le.flag, '') != '' AND LOWER(TRIM(le.flag)) IN ('abnormal','high','low','crit','critical','ab')
        ) THEN 1
        WHEN (
          le.valuenum IS NOT NULL
          AND (
            (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
            OR
            (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
          )
        ) THEN 1
        ELSE 0
      END
    ), 0) AS total_critical_events,
    COALESCE(SUM(
      CASE WHEN (le.valuenum IS NOT NULL OR COALESCE(le.flag,'') != '') THEN 1 ELSE 0 END
    ), 0) AS total_labs
  FROM admissions a
  LEFT JOIN labevents le
    ON le.hadm_id = a.hadm_id
   AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  GROUP BY a.hadm_id, a.subject_id, a.hospital_expire_flag, a.admittime, a.dischtime
),

-- 6) Aggregate inpatient baseline critical-lab rate
inpatient_metrics AS (
  SELECT
    SAFE_DIVIDE(SUM(total_critical_events), NULLIF(SUM(total_labs), 0)) AS inpatient_critical_rate,
    SUM(total_critical_events) AS inpatient_total_critical_events,
    SUM(total_labs) AS inpatient_total_labs
  FROM inpatient_hadm_scores
)

-- Final combined result
SELECT
  cm.threshold AS instability_75th_percentile,
  cm.n_admissions AS n_admissions_at_or_above_threshold,
  ROUND(cm.mortality_pct, 2) AS mortality_percent,
  ROUND(cm.mean_los_days, 2) AS mean_los_days,
  ROUND(cm.cohort_critical_rate, 4) AS cohort_critical_rate,
  ROUND(im.inpatient_critical_rate, 4) AS inpatient_critical_rate,
  ROUND(cm.cohort_critical_rate - im.inpatient_critical_rate, 4) AS absolute_difference_in_critical_rate,
  CASE
    WHEN im.inpatient_critical_rate IS NULL OR im.inpatient_critical_rate = 0 THEN NULL
    ELSE ROUND((cm.cohort_critical_rate / im.inpatient_critical_rate) - 1, 4)
  END AS relative_difference_in_critical_rate
FROM cohort_selected_metrics cm
CROSS JOIN inpatient_metrics im;