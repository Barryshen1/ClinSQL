WITH
cohort AS (
  SELECT 
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year)) BETWEEN 70 AND 80
),
rrt_flag AS (
  SELECT 
    stay_id,
    MAX(CASE WHEN ordercategoryname IN ('Dialysis - continuous', 'Dialysis - hemodialysis') THEN 1 ELSE 0 END) AS has_rrt
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  GROUP BY stay_id
),
cohort_rrt AS (
  SELECT 
    c.*,
    COALESCE(r.has_rrt, 0) AS has_rrt
  FROM cohort c
  LEFT JOIN rrt_flag r
    ON c.stay_id = r.stay_id
),
rrt_patients AS (
  SELECT *
  FROM cohort_rrt
  WHERE has_rrt = 1
),
vital_signs_rrt AS (
  SELECT 
    r.stay_id,
    ce.itemid,
    ce.valuenum
  FROM rrt_patients r
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON r.stay_id = ce.stay_id
  WHERE ce.charttime BETWEEN r.intime AND DATETIME_ADD(r.intime, INTERVAL 48 HOUR)
    AND ce.itemid IN (52, 456, 6702, 220052, 220181, 211, 220045)
    AND ce.valuenum IS NOT NULL
),
composite_scores AS (
  SELECT
    r.stay_id,
    COALESCE(SUM(CASE WHEN vs.itemid IN (52, 456, 6702, 220052, 220181) AND vs.valuenum < 65 THEN 1 ELSE 0 END), 0) AS hypotension_count,
    COALESCE(SUM(CASE WHEN vs.itemid IN (211, 220045) AND vs.valuenum > 100 THEN 1 ELSE 0 END), 0) AS tachycardia_count,
    COALESCE(SUM(CASE WHEN vs.itemid IN (52, 456, 6702, 220052, 220181) AND vs.valuenum < 65 THEN 1 ELSE 0 END), 0) +
    COALESCE(SUM(CASE WHEN vs.itemid IN (211, 220045) AND vs.valuenum > 100 THEN 1 ELSE 0 END), 0) AS composite_score
  FROM rrt_patients r
  LEFT JOIN vital_signs_rrt vs
    ON r.stay_id = vs.stay_id
  GROUP BY r.stay_id
),
p90_value AS (
  SELECT 
    APPROX_QUANTILES(composite_score, 100)[OFFSET(90)] AS p90
  FROM composite_scores
),
top_decile_rrt AS (
  SELECT 
    cs.stay_id,
    cs.hypotension_count,
    cs.tachycardia_count,
    TIMESTAMP_DIFF(rrt.outtime, rrt.intime, SECOND) / 86400 AS icu_los,
    rrt.hospital_expire_flag
  FROM composite_scores cs
  CROSS JOIN p90_value p
  INNER JOIN rrt_patients rrt
    ON cs.stay_id = rrt.stay_id
  WHERE cs.composite_score >= p.p90
),
non_rrt AS (
  SELECT *
  FROM cohort_rrt
  WHERE has_rrt = 0
),
vital_signs_non_rrt AS (
  SELECT 
    n.stay_id,
    ce.itemid,
    ce.valuenum
  FROM non_rrt n
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON n.stay_id = ce.stay_id
  WHERE ce.charttime BETWEEN n.intime AND DATETIME_ADD(n.intime, INTERVAL 48 HOUR)
    AND ce.itemid IN (52, 456, 6702, 220052, 220181, 211, 220045)
    AND ce.valuenum IS NOT NULL
),
non_rrt_metrics AS (
  SELECT 
    n.stay_id,
    COALESCE(SUM(CASE WHEN vs.itemid IN (52, 456, 6702, 220052, 220181) AND vs.valuenum < 65 THEN 1 ELSE 0 END), 0) AS hypotension_count,
    COALESCE(SUM(CASE WHEN vs.itemid IN (211, 220045) AND vs.valuenum > 100 THEN 1 ELSE 0 END), 0) AS tachycardia_count,
    TIMESTAMP_DIFF(n.outtime, n.intime, SECOND) / 86400 AS icu_los,
    n.hospital_expire_flag
  FROM non_rrt n
  LEFT JOIN vital_signs_non_rrt vs
    ON n.stay_id = vs.stay_id
  GROUP BY n.stay_id, n.outtime, n.intime, n.hospital_expire_flag
),
top_decile_summary AS (
  SELECT 
    'top_decile_rrt' AS group_label,
    AVG(hypotension_count) AS hypotension_episodes,
    AVG(tachycardia_count) AS tachycardia_episodes,
    AVG(icu_los) AS icu_los,
    AVG(hospital_expire_flag) AS mortality
  FROM top_decile_rrt
),
non_rrt_summary AS (
  SELECT 
    'non_rrt' AS group_label,
    AVG(hypotension_count) AS hypotension_episodes,
    AVG(tachycardia_count) AS tachycardia_episodes,
    AVG(icu_los) AS icu_los,
    AVG(hospital_expire_flag) AS mortality
  FROM non_rrt_metrics
),
p90_row AS (
  SELECT 
    'RRT_90th_percentile' AS group_label,
    p90 AS composite_score_90th
  FROM p90_value
),
combined AS (
  SELECT group_label, 'composite_score_90th' AS metric, composite_score_90th AS value
  FROM p90_row
  UNION ALL
  SELECT group_label, 'hypotension_episodes', hypotension_episodes
  FROM top_decile_summary
  UNION ALL
  SELECT group_label, 'hypotension_episodes', hypotension_episodes
  FROM non_rrt_summary
  UNION ALL
  SELECT group_label, 'tachycardia_episodes', tachycardia_episodes
  FROM top_decile_summary
  UNION ALL
  SELECT group_label, 'tachycardia_episodes', tachycardia_episodes
  FROM non_rrt_summary
  UNION ALL
  SELECT group_label, 'icu_los', icu_los
  FROM top_decile_summary
  UNION ALL
  SELECT group_label, 'icu_los', icu_los
  FROM non_rrt_summary
  UNION ALL
  SELECT group_label, 'mortality', mortality
  FROM top_decile_summary
  UNION ALL
  SELECT group_label, 'mortality', mortality
  FROM non_rrt_summary
)
SELECT * 
FROM combined
ORDER BY 
  CASE group_label 
    WHEN 'RRT_90th_percentile' THEN 1
    WHEN 'top_decile_rrt' THEN 2
    WHEN 'non_rrt' THEN 3
  END,
  metric;