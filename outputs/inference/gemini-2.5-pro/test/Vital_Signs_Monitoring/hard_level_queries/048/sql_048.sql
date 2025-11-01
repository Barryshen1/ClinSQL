WITH
-- Step 1: Define the cohort of female patients aged 75-85 on invasive ventilation.
cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i ON a.hadm_id = i.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe ON i.stay_id = pe.stay_id
  WHERE
    p.gender = 'F'
    AND DATETIME_DIFF(i.intime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age BETWEEN 75 AND 85
    -- Intubation/Tracheostomy are used as a proxy for invasive ventilation
    AND pe.itemid IN (
      225432, -- Intubation
      224387  -- Tracheostomy
    )
),

-- Step 2: Gather raw measurements for the score calculation within the first 48 hours of the ICU stay.
measurements_48h AS (
  -- Vital signs from chartevents
  SELECT
    c.stay_id,
    'vital' AS type,
    ce.itemid,
    ce.valuenum
  FROM
    cohort AS c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce ON c.stay_id = ce.stay_id
  WHERE
    ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.itemid IN (
      220045, -- Heart Rate
      220179, -- Arterial Blood Pressure systolic
      220050, -- NBP Systolic
      220277, -- O2 saturation pulseoxymetry
      223762  -- Temperature Celsius
    )
    AND ce.valuenum IS NOT NULL
  UNION ALL
  -- Urine output from outputevents
  SELECT
    c.stay_id,
    'uo' AS type,
    oe.itemid,
    SAFE_CAST(oe.value AS NUMERIC) AS valuenum
  FROM
    cohort AS c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.outputevents` AS oe ON c.stay_id = oe.stay_id
  WHERE
    oe.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND oe.itemid = 226559 -- Urine Output
),

-- Step 3: Calculate the composite instability score for each patient stay.
instability_scores AS (
  SELECT
    c.stay_id,
    c.los,
    c.hospital_expire_flag,
    (
      -- Point for Tachycardia (HR > 110)
      MAX(CASE WHEN m.itemid = 220045 AND m.valuenum > 110 THEN 1 ELSE 0 END) +
      -- Point for Hypotension (SBP < 90)
      MAX(CASE WHEN m.itemid IN (220179, 220050) AND m.valuenum < 90 THEN 1 ELSE 0 END) +
      -- Point for Hypoxia (SpO2 < 90)
      MAX(CASE WHEN m.itemid = 220277 AND m.valuenum < 90 THEN 1 ELSE 0 END) +
      -- Point for Temperature instability (<36 or >38.3 C)
      MAX(CASE WHEN m.itemid = 223762 AND (m.valuenum < 36 OR m.valuenum > 38.3) THEN 1 ELSE 0 END) +
      -- Point for Oliguria (UO < 800ml in 48h)
      IF(SUM(CASE WHEN m.type = 'uo' THEN m.valuenum ELSE 0 END) < 800
         AND MAX(CASE WHEN m.type = 'uo' THEN 1 ELSE 0 END) = 1, 1, 0)
    ) AS instability_score
  FROM
    cohort AS c
    LEFT JOIN measurements_48h AS m ON c.stay_id = m.stay_id
  GROUP BY
    c.stay_id, c.los, c.hospital_expire_flag
),

-- Step 4: Calculate 75th and 90th percentiles of the score.
score_percentiles AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90_score,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75_score
  FROM
    instability_scores
),

-- Step 5: Identify the high-risk group (top 25% based on score).
high_risk_group AS (
  SELECT
    i.stay_id,
    i.los,
    i.hospital_expire_flag
  FROM
    instability_scores AS i,
    score_percentiles AS p
  WHERE
    i.instability_score >= p.p75_score
),

-- Step 6: Determine outcomes (hypotension, tachycardia) over the entire ICU stay for the high-risk group.
outcomes_vitals AS (
  SELECT
    hrg.stay_id,
    MAX(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 110 THEN 1 ELSE 0 END) AS has_tachycardia,
    MAX(CASE WHEN ce.itemid IN (220179, 220050) AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS has_hypotension
  FROM
    high_risk_group AS hrg
    INNER JOIN cohort AS c ON hrg.stay_id = c.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce ON hrg.stay_id = ce.stay_id
  WHERE
    ce.charttime BETWEEN c.intime AND c.outtime
    AND ce.itemid IN (220045, 220179, 220050)
  GROUP BY
    hrg.stay_id
),

-- Step 7: Aggregate final outcomes for the high-risk group.
high_risk_outcomes AS (
  SELECT
    AVG(COALESCE(ov.has_hypotension, 0)) AS hypotension_rate,
    AVG(COALESCE(ov.has_tachycardia, 0)) AS tachycardia_rate,
    APPROX_QUANTILES(hrg.los, 100)[OFFSET(50)] AS median_icu_los,
    AVG(hrg.hospital_expire_flag) AS mortality_rate
  FROM
    high_risk_group AS hrg
    LEFT JOIN outcomes_vitals AS ov ON hrg.stay_id = ov.stay_id
)

-- Final Step: Combine all results into a single output row.
SELECT
  sp.p90_score AS percentile_90th_instability_score,
  hro.hypotension_rate AS high_risk_hypotension_rate,
  hro.tachycardia_rate AS high_risk_tachycardia_rate,
  hro.median_icu_los AS high_risk_median_icu_los,
  hro.mortality_rate AS high_risk_mortality_rate
FROM
  score_percentiles AS sp,
  high_risk_outcomes AS hro;