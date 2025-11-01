WITH cohort AS (
  -- Male ICU patients aged 70-80
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pat.anchor_age,
    pat.gender
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 70 AND 80
),

rrt_stays AS (
  -- ICU stays with RRT procedure
  SELECT DISTINCT
    proc.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` proc
  WHERE
    proc.itemid IN (
      225468, -- CRRT
      225477, -- Dialysis
      225810, -- CVVH
      225803, -- CVVHD
      225805, -- CVVHDF
      225806  -- SCUF
    )
),

vitals_48h AS (
  -- Get vital sign episodes in first 48h of ICU stay
  SELECT
    c.stay_id,
    c.hadm_id,
    c.subject_id,
    c.intime,
    c.outtime,
    c.los,
    CASE WHEN rrt.stay_id IS NOT NULL THEN 1 ELSE 0 END AS has_rrt,
    -- Hypotension: MAP < 65
    SUM(CASE WHEN ce.itemid = 220074 AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS hypotension_episodes,
    -- Tachycardia: HR > 120
    SUM(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 120 THEN 1 ELSE 0 END) AS tachycardia_episodes
  FROM
    cohort c
    LEFT JOIN rrt_stays rrt ON c.stay_id = rrt.stay_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON c.stay_id = ce.stay_id
      AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
      AND ce.itemid IN (220074, 220045) -- MAP, HR
      AND ce.valuenum IS NOT NULL
  GROUP BY
    c.stay_id, c.hadm_id, c.subject_id, c.intime, c.outtime, c.los, has_rrt
),

composite_scores AS (
  -- Composite score = hypotension + tachycardia episodes
  SELECT
    v.*,
    (v.hypotension_episodes + v.tachycardia_episodes) AS composite_score
  FROM
    vitals_48h v
),

rrt_scores AS (
  -- RRT patients
  SELECT composite_score
  FROM composite_scores
  WHERE has_rrt = 1
),

percentile_90 AS (
  -- 90th percentile of composite score among RRT patients
  SELECT
    APPROX_QUANTILES(composite_score, 10)[9] AS p90_score
  FROM rrt_scores
),

admissions_mortality AS (
  -- Get hospital mortality for each ICU stay
  SELECT
    icu.stay_id,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON icu.hadm_id = adm.hadm_id
)

SELECT
  CASE WHEN cs.has_rrt = 1 THEN 'RRT' ELSE 'No RRT' END AS group_type,
  COUNT(*) AS n_stays,
  AVG(cs.hypotension_episodes) AS avg_hypotension_episodes,
  APPROX_QUANTILES(cs.hypotension_episodes, 2)[1] AS median_hypotension_episodes,
  AVG(cs.tachycardia_episodes) AS avg_tachycardia_episodes,
  APPROX_QUANTILES(cs.tachycardia_episodes, 2)[1] AS median_tachycardia_episodes,
  AVG(cs.los) AS avg_icu_los,
  APPROX_QUANTILES(cs.los, 2)[1] AS median_icu_los,
  AVG(CAST(am.hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM
  composite_scores cs
  CROSS JOIN percentile_90 p
  LEFT JOIN admissions_mortality am ON cs.stay_id = am.stay_id
WHERE
  cs.composite_score >= p.p90_score
GROUP BY
  group_type
ORDER BY
  group_type;