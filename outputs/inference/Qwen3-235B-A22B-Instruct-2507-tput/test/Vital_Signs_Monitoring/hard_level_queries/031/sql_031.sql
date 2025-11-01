WITH surgical_patients AS (
  SELECT DISTINCT s.hadm_id, s.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.services` s
  WHERE LOWER(s.curr_service) LIKE 'surg%'
),
cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    icu.stay_id,
    icu.los AS icu_los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON a.hadm_id = icu.hadm_id
  INNER JOIN surgical_patients s
    ON icu.hadm_id = s.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
),
vital_items AS (
  SELECT itemid, LOWER(label) AS label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN ('temperature', 'spo2', 'respiratory rate')
),
vital_events AS (
  SELECT 
    ce.stay_id,
    ce.charttime,
    vi.label,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN vital_items vi
    ON ce.itemid = vi.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.stay_id IN (SELECT stay_id FROM cohort)
),
abnormalities AS (
  SELECT 
    stay_id,
    SUM(CASE WHEN label = 'temperature' AND valuenum > 38.5 THEN 1 ELSE 0 END) AS fever_count,
    SUM(CASE WHEN label = 'spo2' AND valuenum < 90 THEN 1 ELSE 0 END) AS spo2_low_count,
    SUM(CASE WHEN label = 'respiratory rate' AND valuenum > 20 THEN 1 ELSE 0 END) AS rr_high_count
  FROM vital_events
  GROUP BY stay_id
),
instability_scores AS (
  SELECT 
    c.stay_id,
    c.icu_los,
    c.hospital_expire_flag,
    COALESCE(ab.fever_count, 0) AS fever_count,
    COALESCE(ab.spo2_low_count, 0) AS spo2_low_count,
    COALESCE(ab.rr_high_count, 0) AS rr_high_count,
    (COALESCE(ab.fever_count, 0) + COALESCE(ab.spo2_low_count, 0) + COALESCE(ab.rr_high_count, 0)) AS instability_score
  FROM cohort c
  LEFT JOIN abnormalities ab
    ON c.stay_id = ab.stay_id
),
instability_quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY instability_score) AS instability_quartile
  FROM instability_scores
),
top_quartile AS (
  SELECT *
  FROM instability_quartiles
  WHERE instability_quartile = 4
),
other_quartiles AS (
  SELECT *
  FROM instability_quartiles
  WHERE instability_quartile < 4
),
summary_top AS (
  SELECT
    'top_quartile' AS group_name,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS p95_instability_score,
    AVG(fever_count) AS avg_fever_episodes,
    AVG(spo2_low_count) AS avg_spo2_low_episodes,
    AVG(rr_high_count) AS avg_rr_high_episodes,
    AVG(icu_los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM top_quartile
),
summary_rest AS (
  SELECT
    'other_quartiles' AS group_name,
    CAST(NULL AS FLOAT64) AS p95_instability_score,
    AVG(fever_count) AS avg_fever_episodes,
    AVG(spo2_low_count) AS avg_spo2_low_episodes,
    AVG(rr_high_count) AS avg_rr_high_episodes,
    AVG(icu_los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM other_quartiles
)
SELECT
  p95_instability_score,
  avg_fever_episodes,
  avg_spo2_low_episodes,
  avg_rr_high_episodes,
  avg_icu_los,
  mortality_rate
FROM summary_top
UNION ALL
SELECT
  p95_instability_score,
  avg_fever_episodes,
  avg_spo2_low_episodes,
  avg_rr_high_episodes,
  avg_icu_los,
  mortality_rate
FROM summary_rest;