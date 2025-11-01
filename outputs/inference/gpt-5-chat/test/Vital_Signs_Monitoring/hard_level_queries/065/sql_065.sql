WITH male_70_80_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 70 AND 80
),
rrt_flags AS (
  SELECT DISTINCT
    pe.stay_id,
    TRUE AS rrt
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON pe.itemid = d.itemid
  WHERE LOWER(d.label) LIKE '%dialysis%'
     OR LOWER(d.label) LIKE '%cvvh%'
     OR LOWER(d.label) LIKE '%rrt%'
),
hypotension AS (
  SELECT
    ce.stay_id,
    COUNTIF(ce.valuenum < 65) AS hypo_episodes
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN male_70_80_icu m
    ON ce.stay_id = m.stay_id
  WHERE LOWER(di.label) = 'mean arterial pressure'
    AND ce.valuenum IS NOT NULL
    AND DATETIME_DIFF(ce.charttime, m.intime, HOUR) <= 48
  GROUP BY ce.stay_id
),
tachycardia AS (
  SELECT
    ce.stay_id,
    COUNTIF(ce.valuenum > 100) AS tachy_episodes
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN male_70_80_icu m
    ON ce.stay_id = m.stay_id
  WHERE LOWER(di.label) = 'heart rate'
    AND ce.valuenum IS NOT NULL
    AND DATETIME_DIFF(ce.charttime, m.intime, HOUR) <= 48
  GROUP BY ce.stay_id
),
composite AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.stay_id,
    m.intime,
    m.outtime,
    m.los,
    IFNULL(h.hypo_episodes, 0) AS hypo,
    IFNULL(t.tachy_episodes, 0) AS tachy,
    IFNULL(h.hypo_episodes,0) + IFNULL(t.tachy_episodes,0) AS composite_score,
    IF(rrt.stay_id IS NOT NULL, TRUE, FALSE) AS rrt_flag
  FROM male_70_80_icu m
  LEFT JOIN hypotension h ON m.stay_id = h.stay_id
  LEFT JOIN tachycardia t ON m.stay_id = t.stay_id
  LEFT JOIN rrt_flags rrt ON m.stay_id = rrt.stay_id
),
rrt_percentile AS (
  SELECT
    PERCENTILE_CONT(composite_score, 0.9) OVER() AS p90_rrt
  FROM composite
  WHERE rrt_flag = TRUE
),
top_decile_rrt_cutoff AS (
  SELECT DISTINCT p90_rrt FROM rrt_percentile
),
top_decile_groups AS (
  SELECT
    c.*,
    a.hospital_expire_flag
  FROM composite c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.hadm_id = a.hadm_id
  CROSS JOIN top_decile_rrt_cutoff cut
  WHERE (c.rrt_flag = TRUE AND c.composite_score >= cut.p90_rrt)
     OR (c.rrt_flag = FALSE AND c.composite_score >= cut.p90_rrt)
)
SELECT
  rrt_flag,
  AVG(hypo) AS avg_hypotension_episodes,
  AVG(tachy) AS avg_tachycardia_episodes,
  AVG(los) AS avg_icu_los_days,
  AVG(hospital_expire_flag) AS mortality_rate
FROM top_decile_groups
GROUP BY rrt_flag;