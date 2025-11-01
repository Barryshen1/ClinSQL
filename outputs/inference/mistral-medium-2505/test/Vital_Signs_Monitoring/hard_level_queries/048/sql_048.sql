WITH
-- Get female patients aged 75-85
female_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 75 AND 85
),

-- Get their first ICU stays with ventilation
icu_stays_with_ventilation AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime AS icu_intime,
    s.outtime AS icu_outtime,
    TIMESTAMP_DIFF(s.outtime, s.intime, HOUR) AS icu_los_hours
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    female_patients p ON s.subject_id = p.subject_id
  WHERE
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      WHERE ce.stay_id = s.stay_id
      AND ce.itemid = 223849  -- Ventilator Mode (invasive ventilation)
      AND ce.charttime BETWEEN s.intime AND s.outtime
    )
),

-- Calculate composite instability score components for first 48 hours
instability_components AS (
  SELECT
    v.subject_id,
    v.stay_id,
    -- Hypotension (MAP < 65)
    MAX(CASE WHEN ce.itemid = 220050 AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS has_hypotension,
    -- Tachycardia (HR > 100)
    MAX(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS has_tachycardia
  FROM
    icu_stays_with_ventilation v
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON v.stay_id = ce.stay_id
    AND ce.charttime BETWEEN v.icu_intime AND TIMESTAMP_ADD(v.icu_intime, INTERVAL 48 HOUR)
  GROUP BY
    v.subject_id, v.stay_id
),

-- Calculate composite score (simple sum of components)
composite_scores AS (
  SELECT
    subject_id,
    stay_id,
    has_hypotension + has_tachycardia AS composite_score,
    has_hypotension,
    has_tachycardia
  FROM
    instability_components
),

-- Get 90th percentile of composite scores
percentile_90 AS (
  SELECT
    PERCENTILE_CONT(composite_score, 0.9) OVER() AS p90_score
  FROM
    composite_scores
  LIMIT 1
),

-- Get top 25% of patients by composite score
top_25_percent AS (
  SELECT
    c.*,
    v.icu_los_hours,
    a.hospital_expire_flag
  FROM
    composite_scores c
  JOIN
    icu_stays_with_ventilation v ON c.stay_id = v.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON v.hadm_id = a.hadm_id
  WHERE
    c.composite_score >= (SELECT p90_score FROM percentile_90)
)

-- Final results
SELECT
  -- 90th percentile of composite scores
  (SELECT p90_score FROM percentile_90) AS percentile_90_composite_score,

  -- Characteristics of top 25%
  COUNT(*) AS top_25_percent_count,
  AVG(has_hypotension) AS hypotension_prevalence,
  AVG(has_tachycardia) AS tachycardia_prevalence,
  AVG(icu_los_hours) AS avg_icu_los_hours,
  AVG(hospital_expire_flag) AS mortality_rate

FROM
  top_25_percent;