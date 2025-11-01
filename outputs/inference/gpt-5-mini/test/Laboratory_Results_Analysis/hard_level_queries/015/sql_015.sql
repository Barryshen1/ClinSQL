WITH
-- Base admissions restricted to male patients aged 49-59
admissions_study AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING (subject_id)
  WHERE
    LOWER(p.gender) = 'm'
    AND p.anchor_age BETWEEN 49 AND 59
),

-- Admissions that have an ischemic / infarct diagnosis (any diagnosis on the admission)
stroke_hadms AS (
  SELECT DISTINCT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  USING (icd_code, icd_version)
  WHERE
    (LOWER(COALESCE(di.long_title, '')) LIKE '%ischemic%'
     OR LOWER(COALESCE(di.long_title, '')) LIKE '%infarct%')
),

-- Lab events in first 72 hours of admission for admissions in our study population
labs_in_72h AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.labevent_id,
    le.charttime,
    le.valuenum,
    le.flag,
    le.ref_range_lower,
    le.ref_range_upper,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN
    admissions_study a
  USING (subject_id, hadm_id)
  WHERE
    le.valuenum IS NOT NULL
    AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
),

-- Per-admission lab counts and instability score (proportion abnormal)
lab_scores AS (
  SELECT
    l.hadm_id,
    l.subject_id,
    COUNT(1) AS total_lab_count,
    SUM(
      CASE
        WHEN (LOWER(COALESCE(l.flag, '')) LIKE '%abnormal%') THEN 1
        WHEN (l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower) THEN 1
        WHEN (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper) THEN 1
        ELSE 0
      END
    ) AS abnormal_count,
    SAFE_DIVIDE(
      SUM(
        CASE
          WHEN (LOWER(COALESCE(l.flag, '')) LIKE '%abnormal%') THEN 1
          WHEN (l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower) THEN 1
          WHEN (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper) THEN 1
          ELSE 0
        END
      ),
      COUNT(1)
    ) AS instability_score
  FROM
    labs_in_72h l
  GROUP BY
    l.hadm_id,
    l.subject_id
),

-- Stroke cohort lab scores (only admissions that are stroke and have labs)
stroke_scores AS (
  SELECT
    ls.*
  FROM
    lab_scores ls
  JOIN
    stroke_hadms s
  USING (hadm_id)
),

-- Controls: admissions in the study set that are NOT stroke and have labs
control_scores AS (
  SELECT
    ls.*
  FROM
    lab_scores ls
  LEFT JOIN
    stroke_hadms s
  USING (hadm_id)
  WHERE
    s.hadm_id IS NULL
),

-- Compute 75th percentile among stroke_scores (approximate)
stroke_pct75 AS (
  SELECT
    (APPROX_QUANTILES(instability_score, 100))[OFFSET(75)] AS pct75
  FROM
    stroke_scores
),

-- High-instability stroke admissions (score >= 75th percentile)
high_instability_stroke AS (
  SELECT
    s.*,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    stroke_scores s
  CROSS JOIN
    stroke_pct75 p
  JOIN
    admissions_study a USING (hadm_id)
  WHERE
    s.instability_score >= p.pct75
),

-- Aggregates for high-instability stroke group
high_stats AS (
  SELECT
    COUNT(DISTINCT hadm_id) AS n_admissions,
    AVG(instability_score) AS mean_instability_score,
    SUM(CASE WHEN abnormal_count > 0 THEN 1 ELSE 0 END) / COUNT(1) AS prop_any_abnormal,
    AVG(SAFE_DIVIDE(TIMESTAMP_DIFF(dischtime, admittime, SECOND), 86400)) AS mean_los_days,
    (APPROX_QUANTILES(SAFE_DIVIDE(TIMESTAMP_DIFF(dischtime, admittime, SECOND), 86400), 100))[OFFSET(50)] AS median_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM
    high_instability_stroke
),

-- Aggregates for controls (age-matched male 49-59 without ischemic stroke)
control_stats AS (
  SELECT
    COUNT(DISTINCT hadm_id) AS n_admissions,
    AVG(instability_score) AS mean_instability_score,
    SUM(CASE WHEN abnormal_count > 0 THEN 1 ELSE 0 END) / COUNT(1) AS prop_any_abnormal
  FROM
    control_scores
)

-- Final output: 75th percentile, then group statistics and comparison
SELECT
  'stroke_75th_percentile_instability_score' AS metric,
  CAST(p.pct75 AS STRING) AS value
FROM
  stroke_pct75 p

UNION ALL

SELECT
  'high_instability_stroke_n | mean_instability | prop_any_abnormal | mean_los_days | median_los_days | mortality_rate' AS metric,
  CONCAT(
    CAST(h.n_admissions AS STRING), ' | ',
    CAST(ROUND(h.mean_instability_score, 4) AS STRING), ' | ',
    CAST(ROUND(h.prop_any_abnormal, 4) AS STRING), ' | ',
    CAST(ROUND(h.mean_los_days, 2) AS STRING), ' | ',
    CAST(ROUND(h.median_los_days, 2) AS STRING), ' | ',
    CAST(ROUND(h.mortality_rate, 4) AS STRING)
  ) AS value
FROM
  high_stats h

UNION ALL

SELECT
  'controls_n | mean_instability | prop_any_abnormal (age-matched males 49-59, no stroke)' AS metric,
  CONCAT(
    CAST(c.n_admissions AS STRING), ' | ',
    CAST(ROUND(c.mean_instability_score, 4) AS STRING), ' | ',
    CAST(ROUND(c.prop_any_abnormal, 4) AS STRING)
  ) AS value
FROM
  control_stats c;