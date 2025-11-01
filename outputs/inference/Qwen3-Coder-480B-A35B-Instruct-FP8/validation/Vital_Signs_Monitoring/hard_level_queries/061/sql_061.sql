WITH cohort AS (
  SELECT
    p.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los AS icu_los,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  USING
    (subject_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  USING
    (hadm_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
),

-- Identify vital signs in first 24 hours
vitals_first24 AS (
  SELECT
    c.stay_id,
    c.intime,
    c.icu_los,
    c.hospital_expire_flag,
    ce.itemid,
    di.label,
    ce.valuenum
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  USING
    (stay_id)
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  USING
    (itemid)
  WHERE
    ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND di.label IN (
      'Heart Rate',
      'Respiratory Rate',
      'O2 saturation pulseoxymetry',
      'Arterial Blood Pressure systolic',
      'Arterial Blood Pressure diastolic',
      'Temperature Celsius'
    )
    AND ce.valuenum IS NOT NULL
),

-- Compute instability score (simple count of abnormal vitals)
scored AS (
  SELECT
    stay_id,
    COUNT(*) AS instability_score,
    MAX(icu_los) AS icu_los,
    MAX(hospital_expire_flag) AS hospital_expire_flag
  FROM
    vitals_first24
  GROUP BY
    stay_id
),

-- Add score = 70 percentile
score_percentiles AS (
  SELECT
    *,
    PERCENTILE_CONT(instability_score, 0.5) OVER() AS median_score,
    PERCENTILE_CONT(instability_score, 0.9) OVER() AS p90_score,
    PERCENTILE_CONT(instability_score, 0.95) OVER() AS p95_score,
    PERCENTILE_CONT(instability_score, 0.99) OVER() AS p99_score
  FROM
    scored
),

-- Determine percentile of score 70
percentile_of_70 AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(70)] AS score_at_70_percentile
  FROM
    scored
),

-- Top decile analysis
top_decile AS (
  SELECT
    *
  FROM
    scored
  WHERE
    instability_score >= (
      SELECT
        APPROX_QUANTILES(instability_score, 10)[OFFSET(9)]
      FROM
        scored
    )
)

-- Final output
SELECT
  (SELECT score_at_70_percentile FROM percentile_of_70) AS score_at_70_percentile,
  APPROX_QUANTILES(instability_score, 100)[OFFSET(70)] AS percentile_of_score_70,
  AVG(icu_los) AS mean_icu_los_top_decile,
  AVG(hospital_expire_flag) * 100 AS hospital_mortality_percent_top_decile
FROM
  top_decile;