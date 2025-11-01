WITH eligible_admissions AS (
  -- female inpatients age 40-50 with a discharge time
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
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.dischtime IS NOT NULL
),

acs_hadm AS (
  -- admissions with ACS diagnoses (match on diagnosis description text)
  SELECT DISTINCT
    di.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON di.icd_code = d.icd_code
      AND di.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%acute coronary%' OR
    LOWER(d.long_title) LIKE '%myocardial infarction%' OR
    LOWER(d.long_title) LIKE '%unstable angina%'
),

labs_first48 AS (
  -- all lab records in first 48 hours for the eligible admissions
  SELECT
    e.hadm_id,
    le.labevent_id,
    le.itemid,
    le.charttime,
    le.valuenum,
    le.ref_range_lower,
    le.ref_range_upper,
    le.flag
  FROM
    eligible_admissions e
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON le.hadm_id = e.hadm_id
  WHERE
    le.charttime >= e.admittime
    AND le.charttime < TIMESTAMP_ADD(e.admittime, INTERVAL 48 HOUR)
),

lab_aggregates AS (
  -- per-admission counts: total labs in first 48h, abnormal labs in first 48h
  SELECT
    hadm_id,
    COUNT(1) AS total_labs_48h,
    SUM(
      CASE
        WHEN (flag IS NOT NULL AND TRIM(flag) <> '') THEN 1
        WHEN (valuenum IS NOT NULL AND (
               (ref_range_lower IS NOT NULL AND valuenum < ref_range_lower)
            OR (ref_range_upper IS NOT NULL AND valuenum > ref_range_upper)
           )) THEN 1
        ELSE 0
      END
    ) AS abnormal_labs_48h
  FROM
    labs_first48
  GROUP BY
    hadm_id
),

admission_metrics AS (
  -- combine admission info with lab aggregates; admissions with no labs get zeros
  SELECT
    e.subject_id,
    e.hadm_id,
    e.admittime,
    e.dischtime,
    e.hospital_expire_flag,
    COALESCE(la.total_labs_48h, 0) AS total_labs_48h,
    COALESCE(la.abnormal_labs_48h, 0) AS instability_score,
    -- critical_lab_rate: abnormal / total, NULL if total = 0
    SAFE_DIVIDE(COALESCE(la.abnormal_labs_48h, 0), NULLIF(COALESCE(la.total_labs_48h, 0), 0)) AS critical_lab_rate,
    -- LOS in days (fractional)
    TIMESTAMP_DIFF(e.dischtime, e.admittime, MINUTE) / 1440.0 AS los_days
  FROM
    eligible_admissions e
    LEFT JOIN lab_aggregates la USING(hadm_id)
),

acs_p90 AS (
  -- 90th percentile of instability score among ACS admissions (female, age 40-50)
  SELECT
    CAST( (APPROX_QUANTILES(instability_score, 100))[OFFSET(90)] AS INT64 ) AS p90_instability
  FROM
    admission_metrics am
    JOIN acs_hadm a ON am.hadm_id = a.hadm_id
)

-- Final comparison: high-risk ACS (>= p90) vs general inpatients (all eligible admissions)
SELECT
  cohort,
  n_admissions,
  mortality_count,
  ROUND(mortality_rate, 4) AS mortality_rate,
  ROUND(mean_los_days, 3) AS mean_los_days,
  ROUND(mean_critical_lab_rate, 4) AS mean_critical_lab_rate,
  ROUND(mean_instability_score, 2) AS mean_instability_score
FROM (
  -- ACS high-risk group
  SELECT
    'ACS_high_90' AS cohort,
    COUNT(1) AS n_admissions,
    SUM(CAST(hospital_expire_flag AS INT64)) AS mortality_count,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(los_days) AS mean_los_days,
    AVG(critical_lab_rate) AS mean_critical_lab_rate,
    AVG(instability_score) AS mean_instability_score
  FROM
    admission_metrics am
    JOIN acs_hadm a ON am.hadm_id = a.hadm_id
    CROSS JOIN acs_p90 p
  WHERE
    am.instability_score >= p.p90_instability

  UNION ALL

  -- General inpatients (female, age 40-50)
  SELECT
    'General_inpatients' AS cohort,
    COUNT(1) AS n_admissions,
    SUM(CAST(hospital_expire_flag AS INT64)) AS mortality_count,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(los_days) AS mean_los_days,
    AVG(critical_lab_rate) AS mean_critical_lab_rate,
    AVG(instability_score) AS mean_instability_score
  FROM
    admission_metrics
)
ORDER BY cohort;