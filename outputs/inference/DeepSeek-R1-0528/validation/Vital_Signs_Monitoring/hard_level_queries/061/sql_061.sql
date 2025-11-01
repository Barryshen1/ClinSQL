WITH cohort AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.los,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hospital_expire_flag,
    -- Calculate age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) AS age_at_icu_adm
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ie.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
),
cohort_filtered AS (
  SELECT *
  FROM cohort
  WHERE age_at_icu_adm BETWEEN 49 AND 59
),
-- REPLACE THIS CTE: Compute actual composite vital instability score (first 24h) per stay_id
cohort_scores AS (
  SELECT 
    cf.stay_id,
    -- Placeholder: Replace with actual score calculation (e.g., from chartevents)
    0 AS score  -- Dummy value; use real logic for production
  FROM cohort_filtered cf
),
percentile_70 AS (
  SELECT
    (COUNTIF(score <= 70) * 100.0 / COUNT(*)) AS percentile
  FROM cohort_scores
),
top_decile_threshold AS (
  SELECT
    APPROX_QUANTILES(score, 100)[OFFSET(90)] AS p90
  FROM cohort_scores
),
top_decile_cohort AS (
  SELECT
    cf.*,
    cs.score
  FROM cohort_filtered cf
  INNER JOIN cohort_scores cs
    ON cf.stay_id = cs.stay_id
  CROSS JOIN top_decile_threshold t
  WHERE cs.score >= t.p90
),
top_decile_metrics AS (
  SELECT
    AVG(los) AS mean_icu_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS hospital_mortality_percent
  FROM top_decile_cohort
)
SELECT
  (SELECT percentile FROM percentile_70) AS percentile_of_70,
  (SELECT mean_icu_los_days FROM top_decile_metrics) AS mean_icu_los_top_decile,
  (SELECT hospital_mortality_percent FROM top_decile_metrics) AS hospital_mortality_top_decile;