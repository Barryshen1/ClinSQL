WITH
-- 1) post-op ICU stays: icustays where the admission has at least one procedure
--    in the 3 days prior to ICU intime through the ICU date
post_op_stays AS (
  SELECT s.*,
         a.hospital_expire_flag,
         p.gender,
         p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    WHERE pr.hadm_id = s.hadm_id
      -- procedure date within 3 days before ICU intime through ICU date
      AND pr.chartdate BETWEEN DATE_SUB(DATE(s.intime), INTERVAL 3 DAY) AND DATE(s.intime)
  )
),

-- 2) Extract temperature measurements and normalize to Celsius when needed
temp_events_raw AS (
  SELECT ce.subject_id,
         ce.hadm_id,
         ce.stay_id,
         ce.charttime,
         ce.valuenum,
         ce.valueuom,
         di.label,
         -- normalize to Celsius when units indicate Fahrenheit
         CASE
           WHEN ce.valuenum IS NULL THEN NULL
           WHEN LOWER(COALESCE(ce.valueuom, '')) LIKE '%f%' THEN (ce.valuenum - 32.0) * 5.0/9.0
           WHEN LOWER(COALESCE(di.unitname, '')) LIKE '%f%' THEN (ce.valuenum - 32.0) * 5.0/9.0
           ELSE ce.valuenum
         END AS temp_c
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  -- filter to likely temperature items by label
  WHERE (LOWER(di.label) LIKE '%temp%' OR LOWER(di.label) LIKE '%temperature%')
    AND ce.valuenum IS NOT NULL
),

-- 3) Keep only fever abnormal measurements (>38.5 C) and collapse into episodes (>60 min gap)
temp_episodes AS (
  SELECT stay_id,
         charttime,
         -- mark new episode if previous abnormal is null or >60 minutes earlier
         CASE
           WHEN prev_charttime IS NULL OR TIMESTAMP_DIFF(charttime, prev_charttime, MINUTE) > 60 THEN 1
           ELSE 0
         END AS new_episode_flag
  FROM (
    SELECT stay_id,
           charttime,
           temp_c,
           LAG(charttime) OVER (PARTITION BY stay_id ORDER BY charttime) AS prev_charttime
    FROM temp_events_raw
    WHERE temp_c > 38.5
  )
),

-- 4) SpO2 events (oxygen saturation). Use item labels that commonly refer to SpO2/O2 saturation
spo2_events_raw AS (
  SELECT ce.subject_id, ce.hadm_id, ce.stay_id, ce.charttime, ce.valuenum, di.label
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE (LOWER(di.label) LIKE '%spo2%' OR LOWER(di.label) LIKE '%oxygen saturation%' OR LOWER(di.label) LIKE '%o2 saturation%')
    AND ce.valuenum IS NOT NULL
),

spo2_episodes AS (
  SELECT stay_id,
         charttime,
         CASE WHEN prev_charttime IS NULL OR TIMESTAMP_DIFF(charttime, prev_charttime, MINUTE) > 60 THEN 1 ELSE 0 END AS new_episode_flag
  FROM (
    SELECT stay_id,
           charttime,
           LAG(charttime) OVER (PARTITION BY stay_id ORDER BY charttime) AS prev_charttime
    FROM spo2_events_raw
    WHERE valuenum < 90
  )
),

-- 5) Respiratory rate events
rr_events_raw AS (
  SELECT ce.subject_id, ce.hadm_id, ce.stay_id, ce.charttime, ce.valuenum, di.label
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE (LOWER(di.label) LIKE '%respiratory rate%' OR LOWER(di.label) LIKE '%resp rate%' OR LOWER(di.label) LIKE '%rr%')
    AND ce.valuenum IS NOT NULL
),

rr_episodes AS (
  SELECT stay_id,
         charttime,
         CASE WHEN prev_charttime IS NULL OR TIMESTAMP_DIFF(charttime, prev_charttime, MINUTE) > 60 THEN 1 ELSE 0 END AS new_episode_flag
  FROM (
    SELECT stay_id,
           charttime,
           LAG(charttime) OVER (PARTITION BY stay_id ORDER BY charttime) AS prev_charttime
    FROM rr_events_raw
    WHERE valuenum > 20
  )
),

-- 6) Aggregate episodes counts per stay for each vital
episodes_per_stay AS (
  SELECT s.stay_id,
         COALESCE(t.fever_episodes, 0) AS fever_episodes,
         COALESCE(sp.spo2_episodes, 0) AS spo2_episodes,
         COALESCE(r.rr_episodes, 0) AS rr_episodes
  FROM (
    SELECT DISTINCT stay_id FROM post_op_stays
  ) s
  LEFT JOIN (
    SELECT stay_id, SUM(new_episode_flag) AS fever_episodes
    FROM temp_episodes
    GROUP BY stay_id
  ) t ON s.stay_id = t.stay_id
  LEFT JOIN (
    SELECT stay_id, SUM(new_episode_flag) AS spo2_episodes
    FROM spo2_episodes
    GROUP BY stay_id
  ) sp ON s.stay_id = sp.stay_id
  LEFT JOIN (
    SELECT stay_id, SUM(new_episode_flag) AS rr_episodes
    FROM rr_episodes
    GROUP BY stay_id
  ) r ON s.stay_id = r.stay_id
),

-- 7) Combine episodes with icu stay info and compute instability score
stay_instability AS (
  SELECT ps.subject_id,
         ps.hadm_id,
         ps.stay_id,
         ps.intime,
         ps.outtime,
         ps.los,
         ps.gender,
         ps.anchor_age,
         ps.hospital_expire_flag,
         ep.fever_episodes,
         ep.spo2_episodes,
         ep.rr_episodes,
         (COALESCE(ep.fever_episodes,0) + COALESCE(ep.spo2_episodes,0) + COALESCE(ep.rr_episodes,0)) AS instability_score
  FROM post_op_stays ps
  LEFT JOIN episodes_per_stay ep
    ON ps.stay_id = ep.stay_id
),

-- 8) Compute 75th percentile threshold (top quartile) of instability score within male post-op patients age 63-73
male_63_73_q AS (
  SELECT
    -- approximate 75th percentile via 4-quantiles (offset 3 = 75th)
    APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS q75
  FROM stay_instability
  WHERE gender = 'M' AND anchor_age BETWEEN 63 AND 73
),

-- 9) Flag stays in top quartile (male 63-73 and instability_score >= q75)
labeled_stays AS (
  SELECT si.*,
         (CASE WHEN (si.gender = 'M' AND si.anchor_age BETWEEN 63 AND 73 AND si.instability_score >= COALESCE(m.q75, 1e9)) THEN 1 ELSE 0 END) AS in_target_top_quartile
  FROM stay_instability si
  LEFT JOIN male_63_73_q m ON TRUE
),

-- 10) Compute 95th percentile within the target top-quartile group
target_95 AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS instability_95th
  FROM labeled_stays
  WHERE in_target_top_quartile = 1
),

-- 11) Aggregations comparing target top-quartile vs other post-op stays
grouped_metrics AS (
  SELECT
    grp,
    COUNT(*) AS n_stays,
    ROUND(AVG(instability_score), 2) AS mean_instability,
    -- median via approx quantiles with 2 quantiles and pick offset 1 (~50th)
    APPROX_QUANTILES(instability_score, 2)[OFFSET(1)] AS median_instability,
    -- 95th for group A only; for group B will be NULL (we include both but primary request was for the target group)
    APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS p95_instability,
    ROUND(AVG(fever_episodes),2) AS mean_fever_episodes,
    -- percent with any fever
    SAFE_DIVIDE(SUM(CASE WHEN fever_episodes > 0 THEN 1 ELSE 0 END), COUNT(*)) AS pct_with_fever,
    ROUND(AVG(spo2_episodes),2) AS mean_spo2_episodes,
    SAFE_DIVIDE(SUM(CASE WHEN spo2_episodes > 0 THEN 1 ELSE 0 END), COUNT(*)) AS pct_with_spo2,
    ROUND(AVG(rr_episodes),2) AS mean_rr_episodes,
    SAFE_DIVIDE(SUM(CASE WHEN rr_episodes > 0 THEN 1 ELSE 0 END), COUNT(*)) AS pct_with_rr,
    -- ICU LOS: median and mean
    APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_icu_los_days,
    ROUND(AVG(los),2) AS mean_icu_los_days,
    -- in-hospital mortality rate using admissions.hospital_expire_flag (0/1)
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS in_hospital_mortality_rate
  FROM (
    SELECT
      CASE WHEN in_target_top_quartile = 1 THEN 'TopQuartile_Male63_73' ELSE 'Other_PostOp' END AS grp,
      instability_score,
      fever_episodes,
      spo2_episodes,
      rr_episodes,
      los,
      hospital_expire_flag
    FROM labeled_stays
  )
  GROUP BY grp
)

-- Final output: the 95th percentile for the target group, and the comparison table
SELECT
  (SELECT instability_95th FROM target_95) AS target_group_95th_instability_score,
  gm.*
FROM grouped_metrics gm
ORDER BY grp;