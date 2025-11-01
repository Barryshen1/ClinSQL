WITH shock AS (
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 9 AND icd_code = '785.5')
    OR (icd_version = 10 AND icd_code LIKE 'R57%')
),
cohort AS (
  SELECT
    i.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag AS mortality,
    CASE WHEN s.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_shock
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  LEFT JOIN shock s
    ON i.subject_id = s.subject_id AND i.hadm_id = s.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
),
map_events AS (
  SELECT
    ce.stay_id,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohort co
    ON ce.subject_id = co.subject_id
    AND ce.hadm_id = co.hadm_id
    AND ce.stay_id = co.stay_id
  WHERE
    ce.itemid = 220045  -- Mean arterial blood pressure (arterial)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= co.intime
    AND ce.charttime <= LEAST(co.intime + INTERVAL 1 DAY, co.outtime)
),
hypo_summary AS (
  SELECT
    stay_id,
    SUM(CASE WHEN valuenum < 65 THEN 1 ELSE 0 END) AS num_low,
    COUNT(*) AS total_map
  FROM map_events
  GROUP BY stay_id
),
hr_events AS (
  SELECT
    ce.stay_id,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohort co
    ON ce.subject_id = co.subject_id
    AND ce.hadm_id = co.hadm_id
    AND ce.stay_id = co.stay_id
  WHERE
    ce.itemid = 211  -- Heart Rate
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= co.intime
    AND ce.charttime <= LEAST(co.intime + INTERVAL 1 DAY, co.outtime)
),
tachy_summary AS (
  SELECT
    stay_id,
    SUM(CASE WHEN valuenum > 100 THEN 1 ELSE 0 END) AS num_high,
    COUNT(*) AS total_hr
  FROM hr_events
  GROUP BY stay_id
),
metrics AS (
  SELECT
    co.stay_id,
    co.has_shock,
    co.los,
    co.mortality,
    COALESCE(hs.num_low * 1.0 / NULLIF(hs.total_map, 0), 0) AS hypo_burden,
    COALESCE(ts.num_high * 1.0 / NULLIF(ts.total_hr, 0), 0) AS tachy_burden,
    (COALESCE(hs.num_low * 1.0 / NULLIF(hs.total_map, 0), 0) +
     COALESCE(ts.num_high * 1.0 / NULLIF(ts.total_hr, 0), 0)) / 2 AS instability_score
  FROM cohort co
  LEFT JOIN hypo_summary hs
    ON co.stay_id = hs.stay_id
  LEFT JOIN tachy_summary ts
    ON co.stay_id = ts.stay_id
)
SELECT
  has_shock,
  -- ICU LOS
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 4)[OFFSET(1)] AS p25_los,
  APPROX_QUANTILES(los, 4)[OFFSET(2)] AS p50_los,
  APPROX_QUANTILES(los, 4)[OFFSET(3)] AS p75_los,
  -- Composite instability score
  AVG(instability_score) AS mean_instability_score,
  APPROX_QUANTILES(instability_score, 4)[OFFSET(1)] AS p25_instability_score,
  APPROX_QUANTILES(instability_score, 4)[OFFSET(2)] AS p50_instability_score,
  APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS p75_instability_score,
  -- Hypotension burden
  AVG(hypo_burden) AS mean_hypotension_burden,
  APPROX_QUANTILES(hypo_burden, 4)[OFFSET(1)] AS p25_hypotension_burden,
  APPROX_QUANTILES(hypo_burden, 4)[OFFSET(2)] AS p50_hypotension_burden,
  APPROX_QUANTILES(hypo_burden, 4)[OFFSET(3)] AS p75_hypotension_burden,
  -- Tachycardia burden
  AVG(tachy_burden) AS mean_tachycardia_burden,
  APPROX_QUANTILES(tachy_burden, 4)[OFFSET(1)] AS p25_tachycardia_burden,
  APPROX_QUANTILES(tachy_burden, 4)[OFFSET(2)] AS p50_tachycardia_burden,
  APPROX_QUANTILES(tachy_burden, 4)[OFFSET(3)] AS p75_tachycardia_burden,
  -- Mortality
  AVG(mortality * 1.0) AS mortality_rate
FROM metrics
GROUP BY has_shock
ORDER BY has_shock;