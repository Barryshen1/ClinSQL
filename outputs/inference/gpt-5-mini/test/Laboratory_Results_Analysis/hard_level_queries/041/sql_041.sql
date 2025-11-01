WITH
-- 1) Admissions filtered to target demographic (male, anchor_age 54-64)
admissions_cohort AS (
  SELECT
    a.*,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
  WHERE
    LOWER(p.gender) = 'm'
    AND p.anchor_age BETWEEN 54 AND 64
),

-- 2) Identify admissions with heart failure diagnoses (text match on diagnosis description)
hf_admissions AS (
  SELECT DISTINCT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND COALESCE(CAST(d.icd_version AS STRING), '') = COALESCE(CAST(dd.icd_version AS STRING), '')
  WHERE
    LOWER(COALESCE(dd.long_title, '')) LIKE '%heart failure%'
),

-- 3) Compute total and critical lab counts in the first 48 hours after admission for admissions in the cohort
labs_first_48h AS (
  SELECT
    a.hadm_id,
    COUNTIF(le.valuenum IS NOT NULL) AS total_labs,
    COUNTIF(
      (
        le.valuenum IS NOT NULL
        AND (
          (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
          OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
        )
      )
      OR (LOWER(COALESCE(le.flag, '')) LIKE '%abnorm%')
    ) AS critical_labs
  FROM
    admissions_cohort a
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON le.hadm_id = a.hadm_id
      AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY
    a.hadm_id
),

-- 4) Merge lab metrics back to admissions cohort and label HF vs control
admission_lab_metrics AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.anchor_age,
    a.gender,
    COALESCE(l.total_labs, 0) AS total_labs,
    COALESCE(l.critical_labs, 0) AS critical_labs,
    CASE
      WHEN COALESCE(l.total_labs, 0) > 0 THEN SAFE_DIVIDE(COALESCE(l.critical_labs, 0), l.total_labs)
      ELSE NULL
    END AS instability_score,
    CASE WHEN hf.hadm_id IS NOT NULL THEN TRUE ELSE FALSE END AS is_heart_failure
  FROM
    admissions_cohort a
    LEFT JOIN labs_first_48h l USING(hadm_id)
    LEFT JOIN hf_admissions hf USING(hadm_id)
),

-- 5) HF admissions that have at least one numeric lab in first 48h (eligible for percentile calculation)
hf_with_labs AS (
  SELECT
    *
  FROM
    admission_lab_metrics
  WHERE
    is_heart_failure = TRUE
    AND total_labs > 0
),

-- 6) Compute the 95th-percentile instability score among HF admissions (approximate)
hf_instability_threshold AS (
  SELECT
    (APPROX_QUANTILES(instability_score, 100))[OFFSET(95)] AS p95_instability
  FROM
    hf_with_labs
),

-- 7) Identify high-instability HF admissions (instability_score >= p95)
high_instability_hf AS (
  SELECT
    m.*
  FROM
    admission_lab_metrics m,
    hf_instability_threshold t
  WHERE
    m.is_heart_failure = TRUE
    AND m.total_labs > 0
    AND m.instability_score >= t.p95_instability
),

-- 8) Controls: same demographic but NOT heart failure and with at least one lab in 48h
controls_with_labs AS (
  SELECT
    m.*
  FROM
    admission_lab_metrics m
  WHERE
    m.is_heart_failure = FALSE
    AND m.total_labs > 0
)

-- Final aggregated outputs
SELECT
  -- 95th percentile threshold
  t.p95_instability AS hf_instability_95th_percentile,

  -- High-instability HF group statistics
  (SELECT COUNT(1) FROM high_instability_hf) AS n_high_instability_hf,
  (SELECT COUNTIF(hospital_expire_flag = 1) FROM high_instability_hf) AS deaths_high_instability_hf,
  ROUND((SELECT AVG(hospital_expire_flag) FROM high_instability_hf) * 100, 2) AS pct_inhospital_mortality_high_instability_pct,
  ROUND((SELECT AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0) FROM high_instability_hf), 2) AS mean_hospital_los_days_high_instability,
  ROUND((SELECT AVG(instability_score) FROM high_instability_hf), 4) AS mean_critical_lab_rate_high_instability,

  -- Control group statistics (age-matched, male, no HF)
  (SELECT COUNT(1) FROM controls_with_labs) AS n_controls,
  ROUND((SELECT AVG(instability_score) FROM controls_with_labs), 4) AS mean_critical_lab_rate_controls,

  -- Simple comparisons
  ROUND(
    SAFE_DIVIDE(
      (SELECT AVG(instability_score) FROM high_instability_hf),
      (SELECT AVG(instability_score) FROM controls_with_labs)
    ),
    3
  ) AS ratio_mean_critical_rate_high_vs_controls,
  ROUND(
    (SELECT AVG(instability_score) FROM high_instability_hf)
    - (SELECT AVG(instability_score) FROM controls_with_labs),
    4
  ) AS diff_mean_critical_rate_high_minus_controls

FROM
  hf_instability_threshold t;