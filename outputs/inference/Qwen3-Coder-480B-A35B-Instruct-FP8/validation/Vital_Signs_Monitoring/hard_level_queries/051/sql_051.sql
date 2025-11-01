WITH cohort AS (
  SELECT
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    DATETIME_DIFF(i.outtime, i.intime, HOUR) AS icu_los_hours,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    p.subject_id = i.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    i.hadm_id = a.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
),

-- Identify ischemic stroke patients
ischemic_stroke AS (
  SELECT DISTINCT
    di.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%ischemic stroke%'
),

-- Compute instability score: count of abnormal events in first 48 hours
instability_scores AS (
  SELECT
    c.stay_id,
    COUNT(*) AS instability_score,
    COUNTIF(c_event.warning = 1 OR c_event.valuenum NOT BETWEEN COALESCE(d_item.lownormalvalue, -99999) AND COALESCE(d_item.highnormalvalue, 99999)) AS abnormal_episodes
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` c_event
  ON
    c.stay_id = c_event.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` d_item
  ON
    c_event.itemid = d_item.itemid
  WHERE
    c_event.charttime >= c.intime
    AND c_event.charttime <= DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY
    c.stay_id
),

-- Add ischemic stroke flag and carry forward needed fields
scored_cohort AS (
  SELECT
    s.stay_id,
    s.instability_score,
    s.abnormal_episodes,
    c.icu_los_hours,
    c.hospital_expire_flag,
    CASE WHEN i.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_ischemic_stroke
  FROM
    instability_scores s
  JOIN
    cohort c ON s.stay_id = c.stay_id
  LEFT JOIN
    ischemic_stroke i ON c.hadm_id = i.hadm_id
),

-- Compute 95th percentile of instability score among ischemic stroke patients
percentile_95 AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS score_95th
  FROM
    scored_cohort
  WHERE
    is_ischemic_stroke = 1
),

-- Identify top instability quartile
top_quartile AS (
  SELECT
    APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS q3_threshold
  FROM
    scored_cohort
),

-- Filter top quartile
top_quartile_cohort AS (
  SELECT
    sc.*,
    CASE WHEN sc.is_ischemic_stroke = 1 THEN 'Ischemic Stroke' ELSE 'General ICU' END AS group_label
  FROM
    scored_cohort sc
  CROSS JOIN
    top_quartile tq
  WHERE
    sc.instability_score >= tq.q3_threshold
)

-- Final comparison
SELECT
  group_label,
  COUNT(*) AS N,
  AVG(instability_score) AS mean_instability,
  AVG(abnormal_episodes) AS mean_abnormal_episodes,
  AVG(icu_los_hours) AS mean_icu_los_hours,
  AVG(hospital_expire_flag) AS mortality_rate
FROM
  top_quartile_cohort
GROUP BY
  group_label
ORDER BY
  group_label;