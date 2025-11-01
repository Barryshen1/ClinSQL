WITH
rrt_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%dialysis%'
     OR LOWER(label) LIKE '%renal%'
     OR LOWER(label) LIKE '%crrt%'
),
rrt_stays AS (
  SELECT DISTINCT ie.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  WHERE ie.itemid IN (SELECT itemid FROM rrt_itemids)
),

-- 2) Cohorts: M (male), age 70-80, with and without RRT
rrt_cohort AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 70 AND 80
    AND i.stay_id IN (SELECT stay_id FROM rrt_stays)
),
nonrrt_cohort AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 70 AND 80
    AND i.stay_id NOT IN (SELECT stay_id FROM rrt_stays)
),

-- 3) 48-hour instability counts: hypotension (MAP<65) and tachycardia (HR>100)
hypot_counts AS (
  SELECT icu.stay_id, COUNT(DISTINCT ce.charttime) AS count_hyp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON ce.stay_id = icu.stay_id
  WHERE (LOWER(di.label) LIKE '%map%' OR LOWER(di.label) LIKE '%mean arterial pressure%')
    AND ce.valuenum < 65
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
  GROUP BY icu.stay_id
),
tachy_counts AS (
  SELECT icu.stay_id, COUNT(DISTINCT ce.charttime) AS count_tach
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON ce.stay_id = icu.stay_id
  WHERE (LOWER(di.label) LIKE '%heart rate%' OR LOWER(di.label) LIKE '%hr%')
    AND ce.valuenum > 100
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
  GROUP BY icu.stay_id
),

rrt_instability AS (
  SELECT r.stay_id,
         COALESCE(h.count_hyp, 0) AS hypotension_events,
         COALESCE(t.count_tach, 0) AS tachy_events,
         (COALESCE(h.count_hyp, 0) + COALESCE(t.count_tach, 0)) AS instability_score_48h
  FROM rrt_cohort r
  LEFT JOIN hypot_counts h ON r.stay_id = h.stay_id
  LEFT JOIN tachy_counts t ON r.stay_id = t.stay_id
),

rrt_mortality AS (
  SELECT r.stay_id,
         CASE WHEN a.hospital_expire_flag = 1 OR CAST(a.hospital_expire_flag AS STRING) = 'Y' THEN 1 ELSE 0 END AS mortality_flag
  FROM rrt_cohort r
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON r.hadm_id = a.hadm_id
),

rrt_final AS (
  SELECT rrt_instability.stay_id,
         rrt_instability.instability_score_48h,
         rrt_instability.hypotension_events,
         rrt_instability.tachy_events,
         rrt_mortality.mortality_flag,
         rrt_cohort.los AS icu_los
  FROM rrt_instability
  LEFT JOIN rrt_mortality USING (stay_id)
  LEFT JOIN rrt_cohort ON rrt_instability.stay_id = rrt_cohort.stay_id
),

rrt_scores AS (
  SELECT stay_id, instability_score_48h, hypotension_events, tachy_events, icu_los, mortality_flag
  FROM rrt_final
),

rrt_p90 AS (
  SELECT q[OFFSET(90)] AS p90
  FROM (
    SELECT APPROX_QUANTILES(instability_score_48h, 100) AS q
    FROM rrt_scores
  )
),

rrt_top AS (
  SELECT s.stay_id, s.instability_score_48h, s.hypotension_events, s.tachy_events, s.icu_los, s.mortality_flag
  FROM rrt_scores s
  JOIN rrt_p90 p ON s.instability_score_48h >= p.p90
),

-- 4) Non-RRT metrics for comparison group
nonrrt_hyp AS (
  SELECT icu.stay_id, COUNT(DISTINCT ce.charttime) AS count_hyp
  FROM nonrrt_cohort icu
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON icu.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE (LOWER(di.label) LIKE '%map%' OR LOWER(di.label) LIKE '%mean arterial pressure%')
    AND ce.valuenum < 65
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
  GROUP BY icu.stay_id
),
nonrrt_tach AS (
  SELECT icu.stay_id, COUNT(DISTINCT ce.charttime) AS count_tach
  FROM nonrrt_cohort icu
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON icu.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE (LOWER(di.label) LIKE '%heart rate%' OR LOWER(di.label) LIKE '%hr%')
    AND ce.valuenum > 100
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
  GROUP BY icu.stay_id
),
nonrrt_instability AS (
  SELECT c.stay_id,
         COALESCE(h.count_hyp, 0) AS hypotension_events,
         COALESCE(t.count_tach, 0) AS tachy_events,
         (COALESCE(h.count_hyp, 0) + COALESCE(t.count_tach, 0)) AS instability_score_48h,
         c.los AS icu_los
  FROM nonrrt_cohort c
  LEFT JOIN nonrrt_hyp h ON c.stay_id = h.stay_id
  LEFT JOIN nonrrt_tach t ON c.stay_id = t.stay_id
),
nonrrt_mortality AS (
  SELECT c.stay_id,
         CASE WHEN a.hospital_expire_flag = 1 OR CAST(a.hospital_expire_flag AS STRING) = 'Y' THEN 1 ELSE 0 END AS mortality_flag
  FROM nonrrt_cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id
),
nonrrt_final AS (
  SELECT n.stay_id, n.instability_score_48h, n.hypotension_events, n.tachy_events, n.icu_los, m.mortality_flag
  FROM nonrrt_instability n
  JOIN nonrrt_cohort c ON n.stay_id = c.stay_id
  LEFT JOIN nonrrt_mortality m ON n.stay_id = m.stay_id
),
nonrrt_scores AS (
  SELECT stay_id, instability_score_48h, hypotension_events, tachy_events, icu_los, mortality_flag
  FROM nonrrt_final
)

-- 5) Final output: two groups with requested metrics
SELECT
  'Top decile (RRT)' AS group_label,
  AVG(hypotension_events) AS avg_hypotension_48h,
  AVG(tachy_events) AS avg_tachy_48h,
  AVG(icu_los) AS avg_icu_los_hours,
  AVG(mortality_flag) AS mortality_rate
FROM rrt_top

UNION ALL

SELECT
  'Males 70-80 without RRT' AS group_label,
  AVG(hypotension_events) AS avg_hypotension_48h,
  AVG(tachy_events) AS avg_tachy_48h,
  AVG(icu_los) AS avg_icu_los_hours,
  AVG(mortality_flag) AS mortality_rate
FROM nonrrt_final;