WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.los,
    icu.intime,
    icu.outtime,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  USING
    (hadm_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON
    icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 52 AND 62
),

-- Identify RRT patients
rrt_patients AS (
  SELECT DISTINCT
    ce.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%dialysis%'
    OR LOWER(di.label) LIKE '%crrt%'
    OR LOWER(di.label) LIKE '%renal replacement%'
),

-- Define vital signs of interest
vitals AS (
  SELECT
    itemid,
    label
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) IN ('heart rate', 'systolic bp', 'diastolic bp', 'respiratory rate', 'temperature f', 'temperature c', 'gcs')
),

-- Compute instability score: count abnormal vitals in first 72h
abnormal_vitals AS (
  SELECT
    ce.stay_id,
    COUNT(*) AS instability_score
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    vitals v
  ON
    ce.itemid = v.itemid
  JOIN
    cohort c
  ON
    ce.stay_id = c.stay_id
  JOIN
    rrt_patients r
  ON
    ce.stay_id = r.stay_id
  WHERE
    ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    AND (
      (v.label = 'heart rate' AND (ce.valuenum < 50 OR ce.valuenum > 130))
      OR (v.label = 'systolic bp' AND (ce.valuenum < 90 OR ce.valuenum > 180))
      OR (v.label = 'diastolic bp' AND (ce.valuenum < 60 OR ce.valuenum > 110))
      OR (v.label = 'respiratory rate' AND (ce.valuenum < 10 OR ce.valuenum > 25))
      OR (v.label LIKE 'temperature%' AND (ce.valuenum < 36 OR ce.valuenum > 38.5))
      OR (v.label = 'gcs' AND ce.valuenum < 15)
    )
  GROUP BY
    ce.stay_id
),

-- Add scores to cohort
scored_cohort AS (
  SELECT
    c.*,
    COALESCE(v.instability_score, 0) AS instability_score
  FROM
    cohort c
  JOIN
    rrt_patients r
  ON
    c.stay_id = r.stay_id
  LEFT JOIN
    abnormal_vitals v
  ON
    c.stay_id = v.stay_id
),

-- Percentile of score = 65
percentile_65 AS (
  SELECT
    PERCENT_RANK() OVER (ORDER BY instability_score) * 100 AS percentile_rank_65
  FROM
    scored_cohort
  WHERE
    instability_score <= 65
  ORDER BY
    instability_score DESC
  LIMIT 1
),

-- Top decile analysis
deciles AS (
  SELECT
    *,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile
  FROM
    scored_cohort
),

top_decile_stats AS (
  SELECT
    AVG(los) AS mean_los_top_decile,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_top_decile
  FROM
    deciles
  WHERE
    decile = 1
)

-- Final output
SELECT
  (SELECT percentile_rank_65 FROM percentile_65) AS percentile_rank_of_65,
  (SELECT mean_los_top_decile FROM top_decile_stats) AS mean_los_top_decile,
  (SELECT mortality_top_decile FROM top_decile_stats) AS mortality_top_decile;