WITH stays AS (
  SELECT 
    p.subject_id, 
    i.stay_id, 
    i.hadm_id, 
    i.intime, 
    i.outtime, 
    i.los, 
    p.gender, 
    p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M' 
    AND p.anchor_age >= 70 
    AND p.anchor_age <= 80
),
rrt_stays AS (
  SELECT DISTINCT pe.stay_id
  FROM stays s
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
    ON pe.stay_id = s.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON di.itemid = pe.itemid
  WHERE LOWER(di.label) LIKE '%dialysis%' 
    OR LOWER(di.label) LIKE '%rrt%' 
    OR LOWER(di.label) LIKE '%hemodia%' 
    OR LOWER(di.label) LIKE '%hemofiltration%'
),
stays_with_flags AS (
  SELECT 
    s.*,
    CASE WHEN r.stay_id IS NOT NULL THEN 1 ELSE 0 END AS has_rrt
  FROM stays s
  LEFT JOIN rrt_stays r ON r.stay_id = s.stay_id
),
hypotension AS (
  SELECT 
    ce.stay_id,
    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END AS has_hypotension
  FROM stays_with_flags swf
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON ce.stay_id = swf.stay_id
  WHERE ce.itemid = 220052 
    AND ce.valuenum < 65 
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= swf.intime 
    AND ce.charttime < swf.outtime
  GROUP BY ce.stay_id
),
tachycardia AS (
  SELECT 
    ce.stay_id,
    COUNT(*) AS tachy_count
  FROM stays_with_flags swf
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON ce.stay_id = swf.stay_id
  WHERE ce.itemid = 220045 
    AND ce.valuenum > 100 
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= swf.intime 
    AND ce.charttime < swf.outtime
  GROUP BY ce.stay_id
),
all_stays AS (
  SELECT 
    swf.*,
    COALESCE(h.has_hypotension, 0) AS has_hypotension,
    COALESCE(t.tachy_count, 0) AS tachy_count
  FROM stays_with_flags swf
  LEFT JOIN hypotension h ON h.stay_id = swf.stay_id
  LEFT JOIN tachycardia t ON t.stay_id = swf.stay_id
),
vital_instability AS (
  SELECT 
    ce.stay_id,
    SUM(
      CASE 
        WHEN ce.itemid = 220045 AND (ce.valuenum > 100 OR ce.valuenum < 60) THEN 1 
        ELSE 0 
      END +
      CASE 
        WHEN ce.itemid = 220052 AND ce.valuenum < 65 THEN 1 
        ELSE 0 
      END +
      CASE 
        WHEN ce.itemid = 220210 AND (ce.valuenum > 30 OR ce.valuenum < 12) THEN 1 
        ELSE 0 
      END +
      CASE 
        WHEN ce.itemid = 220277 AND ce.valuenum < 92 THEN 1 
        ELSE 0 
      END +
      CASE 
        WHEN ce.itemid = 676 AND (ce.valuenum > 38 OR ce.valuenum < 36) THEN 1
        WHEN ce.itemid = 223761 AND (ce.valuenum > 100.4 OR ce.valuenum < 96.8) THEN 1
        ELSE 0 
      END
    ) AS instability_score
  FROM all_stays s
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON ce.stay_id = s.stay_id
  WHERE s.has_rrt = 1
    AND ce.charttime >= s.intime 
    AND ce.charttime < TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
    AND ce.itemid IN (220045, 220052, 220210, 220277, 676, 223761)
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
),
rrt_all AS (
  SELECT 
    a.*,
    COALESCE(vi.instability_score, 0) AS instability_score
  FROM all_stays a
  WHERE a.has_rrt = 1
  LEFT JOIN vital_instability vi ON vi.stay_id = a.stay_id
),
p90 AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90_value
  FROM rrt_all
),
top_decile AS (
  SELECT ra.*
  FROM rrt_all ra
  CROSS JOIN p90 p
  WHERE ra.instability_score >= p.p90_value
),
non_rrt AS (
  SELECT *
  FROM all_stays
  WHERE has_rrt = 0
)
SELECT
  (SELECT p90_value FROM p90) AS `90th_percentile_48h_instability_score`,
  (SELECT AVG(los) FROM top_decile) AS `top_decile_rrt_avg_icu_los_days`,
  (SELECT AVG(hospital_expire_flag * 1.0) FROM top_decile) AS `top_decile_rrt_mortality_rate`,
  (SELECT AVG(has_hypotension * 1.0) FROM top_decile) AS `top_decile_rrt_hypotension_rate_map_lt_65`,
  (SELECT AVG(tachy_count * 1.0) FROM top_decile) AS `top_decile_rrt_avg_tachycardia_episodes_hr_gt_100`,
  (SELECT AVG(los) FROM non_rrt) AS `non_rrt_avg_icu_los_days`,
  (SELECT AVG(hospital_expire_flag * 1.0) FROM non_rrt) AS `non_rrt_mortality_rate`,
  (SELECT AVG(has_hypotension * 1.0) FROM non_rrt) AS `non_rrt_hypotension_rate_map_lt_65`,
  (SELECT AVG(tachy_count * 1.0) FROM non_rrt) AS `non_rrt_avg_tachycardia_episodes_hr_gt_100`;