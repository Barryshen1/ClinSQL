WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    p.anchor_age,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON icu.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON icu.subject_id = a.subject_id
      AND icu.hadm_id = a.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 70 AND 80
),
rrt_flag AS (
  -- Flag stays with any dialysis procedure in first 48h
  SELECT
    c.*,
    CASE WHEN COUNT(pe.itemid) > 0 THEN TRUE ELSE FALSE END AS has_rrt
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      ON c.subject_id = pe.subject_id
      AND c.hadm_id = pe.hadm_id
      AND c.stay_id = pe.stay_id
      AND pe.starttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON pe.itemid = di.itemid
      AND LOWER(di.label) LIKE '%dialysis%'
  GROUP BY
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    c.los,
    c.anchor_age,
    c.hospital_expire_flag
),
vitals AS (
  -- Extract MAP and HR measurements in first 48h
  SELECT
    rf.subject_id,
    rf.hadm_id,
    rf.stay_id,
    rf.intime,
    rf.los,
    rf.has_rrt,
    rf.hospital_expire_flag,
    SUM(CASE WHEN di.label = 'Mean Arterial Pressure' AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS hypotension_minutes,
    SUM(CASE WHEN di.label = 'Heart Rate' AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachy_count
  FROM
    rrt_flag rf
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON rf.subject_id = ce.subject_id
      AND rf.hadm_id = ce.hadm_id
      AND rf.stay_id = ce.stay_id
      AND ce.charttime BETWEEN rf.intime AND TIMESTAMP_ADD(rf.intime, INTERVAL 48 HOUR)
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
      AND di.label IN ('Mean Arterial Pressure', 'Heart Rate')
  GROUP BY
    rf.subject_id,
    rf.hadm_id,
    rf.stay_id,
    rf.intime,
    rf.los,
    rf.has_rrt,
    rf.hospital_expire_flag
),
scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    has_rrt,
    hospital_expire_flag,
    los,
    hypotension_minutes / 60.0 AS hypotension_hours,
    tachy_count,
    (hypotension_minutes / 60.0 + tachy_count) AS composite_score
  FROM
    vitals
),
p90 AS (
  -- 90th percentile of composite score among RRT patients
  SELECT
    APPROX_QUANTILES(composite_score, 100)[OFFSET(90)] AS p90_score
  FROM
    scores
  WHERE
    has_rrt = TRUE
),
top_decile AS (
  SELECT
    s.*,
    p.p90_score,
    s.composite_score >= p.p90_score AS is_top_decile
  FROM
    scores s
    CROSS JOIN p90 p
)
SELECT
  has_rrt,
  COUNT(*)                                 AS n_patients,
  AVG(hypotension_hours)                   AS avg_hypotension_hours,
  AVG(tachy_count)                         AS avg_tachycardia_episodes,
  AVG(los)                                 AS avg_icu_los_days,
  AVG(CAST(hospital_expire_flag AS INT64)) AS mortality_rate
FROM
  top_decile
WHERE
  is_top_decile = TRUE
GROUP BY
  has_rrt
ORDER BY
  has_rrt DESC;