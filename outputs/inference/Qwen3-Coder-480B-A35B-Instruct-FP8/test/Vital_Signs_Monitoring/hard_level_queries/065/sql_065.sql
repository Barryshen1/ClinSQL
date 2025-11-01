WITH rrt_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%rrt%'
     OR LOWER(label) LIKE '%dialysis%'
     OR LOWER(label) LIKE '%cvvh%'
     OR LOWER(label) LIKE '%hemodialysis%'
),

vitals_itemids AS (
  SELECT itemid, 'map' AS vital_type
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%map%'
  UNION ALL
  SELECT itemid, 'hr' AS vital_type
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%heart rate%'
),

eligible_patients AS (
  SELECT p.subject_id, p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 70 AND 80
),

icu_stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime, i.los,
         CASE WHEN adm.deathtime IS NOT NULL OR i.first_careunit != i.last_careunit THEN 1 ELSE 0 END AS mortality
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN eligible_patients ep ON i.subject_id = ep.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON i.hadm_id = adm.hadm_id
),

rrt_stays AS (
  SELECT DISTINCT ce.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN rrt_itemids ri ON ce.itemid = ri.itemid
  WHERE ce.stay_id IN (SELECT stay_id FROM icu_stays)
),

vitals AS (
  SELECT ce.stay_id, ce.charttime, ce.itemid, ce.valuenum,
         vi.vital_type
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN vitals_itemids vi ON ce.itemid = vi.itemid
  JOIN icu_stays i ON ce.stay_id = i.stay_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime >= i.intime
    AND ce.charttime <= DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
),

instability_scores AS (
  SELECT v.stay_id,
         COUNT(CASE WHEN v.vital_type = 'map' AND v.valuenum < 65 THEN 1 END) AS hypotension_episodes,
         COUNT(CASE WHEN v.vital_type = 'hr' AND v.valuenum > 130 THEN 1 END) AS tachycardia_episodes
  FROM vitals v
  GROUP BY v.stay_id
),

scored_stays AS (
  SELECT i.stay_id, i.los, i.mortality,
         COALESCE(ins.hypotension_episodes, 0) AS hypotension_episodes,
         COALESCE(ins.tachycardia_episodes, 0) AS tachycardia_episodes,
         COALESCE(ins.hypotension_episodes, 0) + COALESCE(ins.tachycardia_episodes, 0) AS instability_score
  FROM icu_stays i
  LEFT JOIN instability_scores ins ON i.stay_id = ins.stay_id
),

rrt_scored AS (
  SELECT ss.*
  FROM scored_stays ss
  JOIN rrt_stays rs ON ss.stay_id = rs.stay_id
),

non_rrt_scored AS (
  SELECT ss.*
  FROM scored_stays ss
  LEFT JOIN rrt_stays rs ON ss.stay_id = rs.stay_id
  WHERE rs.stay_id IS NULL
),

percentile_90 AS (
  SELECT PERCENTILE_CONT(instability_score, 0.9) OVER() AS p90
  FROM rrt_scored
  LIMIT 1
),

top_decile_rrt AS (
  SELECT rs.*
  FROM rrt_scored rs
  CROSS JOIN percentile_90 p
  WHERE rs.instability_score >= p.p90
)

SELECT
  'Top Decile RRT' AS group_name,
  AVG(hypotension_episodes) AS avg_hypotension_episodes,
  AVG(tachycardia_episodes) AS avg_tachycardia_episodes,
  AVG(los) AS avg_icu_los,
  AVG(CAST(mortality AS FLOAT64)) AS mortality_rate
FROM top_decile_rrt

UNION ALL

SELECT
  'Non-RRT' AS group_name,
  AVG(hypotension_episodes) AS avg_hypotension_episodes,
  AVG(tachycardia_episodes) AS avg_tachycardia_episodes,
  AVG(los) AS avg_icu_los,
  AVG(CAST(mortality AS FLOAT64)) AS mortality_rate
FROM non_rrt_scored;