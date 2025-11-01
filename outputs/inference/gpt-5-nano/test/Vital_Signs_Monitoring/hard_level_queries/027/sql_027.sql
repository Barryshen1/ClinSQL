WITH
rrt_stays AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN (
    SELECT DISTINCT ce.subject_id, ce.hadm_id, ce.stay_id
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di ON di.itemid = ce.itemid
    WHERE LOWER(di.label) LIKE '%dialysis%'
       OR LOWER(di.label) LIKE '%renal%'
  ) AS d
    ON icu.subject_id = d.subject_id
   AND icu.hadm_id = d.hadm_id
   AND icu.stay_id = d.stay_id
),

-- 2) Tag stays into Target (63F, 58-68) vs Other_RRT
rrt_group AS (
  SELECT rs.subject_id, rs.hadm_id, rs.stay_id, rs.intime, rs.los,
         CASE
           WHEN p.gender = 'F' AND p.anchor_age BETWEEN 58 AND 68 THEN 'Target:63F_58-68'
           ELSE 'Other_RRT'
         END AS group_label
  FROM rrt_stays rs
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = rs.subject_id
),

-- 3) Per-hour MAP readings for first 72h
hourly_maps AS (
  SELECT g.subject_id, g.hadm_id, g.stay_id, g.group_label,
         TIMESTAMP_DIFF(ce.charttime, g.intime, HOUR) AS hour_bucket,
         AVG(ce.valuenum) AS map_value
  FROM rrt_group g
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = g.subject_id
   AND ce.hadm_id = g.hadm_id
   AND ce.stay_id = g.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di ON di.itemid = ce.itemid
  WHERE (LOWER(di.label) LIKE '%map%' OR LOWER(di.label) LIKE '%mean arterial pressure%')
    AND TIMESTAMP_DIFF(ce.charttime, g.intime, HOUR) >= 0
    AND TIMESTAMP_DIFF(ce.charttime, g.intime, HOUR) < 72
  GROUP BY g.subject_id, g.hadm_id, g.stay_id, g.group_label, hour_bucket
),

-- 4) Per-hour HR readings for first 72h
hourly_hr AS (
  SELECT g.subject_id, g.hadm_id, g.stay_id, g.group_label,
         TIMESTAMP_DIFF(ce.charttime, g.intime, HOUR) AS hour_bucket,
         AVG(ce.valuenum) AS hr_value
  FROM rrt_group g
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = g.subject_id
   AND ce.hadm_id = g.hadm_id
   AND ce.stay_id = g.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di ON di.itemid = ce.itemid
  WHERE (LOWER(di.label) LIKE '%heart rate%' OR LOWER(di.label) LIKE '%hr%')
    AND TIMESTAMP_DIFF(ce.charttime, g.intime, HOUR) >= 0
    AND TIMESTAMP_DIFF(ce.charttime, g.intime, HOUR) < 72
  GROUP BY g.subject_id, g.hadm_id, g.stay_id, g.group_label, hour_bucket
),

-- 5) Combine MAP and HR per-hour values
hourly_comb AS (
  SELECT m.subject_id, m.hadm_id, m.stay_id, m.group_label, m.hour_bucket,
         m.map_value,
         h.hr_value
  FROM hourly_maps m
  LEFT JOIN hourly_hr h
    ON h.subject_id = m.subject_id
   AND h.hadm_id = m.hadm_id
   AND h.stay_id = m.stay_id
   AND h.hour_bucket = m.hour_bucket
),

-- 6) Hourly flags for MAP<65 and HR>100
hourly_flags AS (
  SELECT hourl.subject_id, hourl.hadm_id, hourl.stay_id, hourl.group_label, hourl.hour_bucket,
         IF(map_value < 65, 1, 0) AS map_under65,
         IF(hr_value > 100, 1, 0) AS hr_gt100
  FROM hourly_comb AS hourl
),

-- 7) Vital-instability per hour: average of the two binary indicators
hourly_vital AS (
  SELECT subject_id, hadm_id, stay_id, group_label, hour_bucket,
         (map_under65 + hr_gt100) / 2.0 AS vital_instability
  FROM hourly_flags
  WHERE map_under65 IS NOT NULL OR hr_gt100 IS NOT NULL
),

-- 8) Per-stay counts of hypotensive/tachycardic/concurrent hours
per_stay AS (
  SELECT hf.group_label, hf.subject_id, hf.hadm_id, hf.stay_id,
         SUM(hf.map_under65) AS hypotensive_hours,
         SUM(hf.hr_gt100) AS tachy_hours,
         SUM(CASE WHEN hf.map_under65 = 1 AND hf.hr_gt100 = 1 THEN 1 ELSE 0 END) AS concurrent_hours
  FROM hourly_flags hf
  GROUP BY hf.group_label, hf.subject_id, hf.hadm_id, hf.stay_id
),

-- 9) Attach ICU LOS and hospital mortality to each stay
stay_with_outcome AS (
  SELECT ps.group_label, ps.subject_id, ps.hadm_id, ps.stay_id,
         ps.hypotensive_hours, ps.tachy_hours, ps.concurrent_hours,
         rg.los,
         adm.hospital_expire_flag
  FROM per_stay ps
  JOIN rrt_group rg
    ON rg.subject_id = ps.subject_id
   AND rg.hadm_id = ps.hadm_id
   AND rg.stay_id = ps.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON adm.hadm_id = ps.hadm_id
),

-- 10) Group-level stats: LOS and mortality, per group
group_stats AS (
  SELECT group_label,
         AVG(los) AS mean_icu_los,
         AVG(hospital_expire_flag) AS mortality_rate,
         AVG(hypotensive_hours) AS mean_hypotensive_hours,
         AVG(tachy_hours) AS mean_tachy_hours,
         AVG(concurrent_hours) AS mean_concurrent_hours
  FROM stay_with_outcome
  GROUP BY group_label
),

-- 11) Prepare per-hour vital_instability values across all stays, by group
hourly_vital_all AS (
  SELECT group_label, vital_instability
  FROM hourly_vital
),

-- 12) Percentiles of vital-instability by group
vital_percentiles AS (
  SELECT group_label,
         quantiles[OFFSET(25)] AS p25,
         quantiles[OFFSET(50)] AS p50,
         quantiles[OFFSET(75)] AS p75,
         quantiles[OFFSET(90)] AS p90,
         quantiles[OFFSET(75)] - quantiles[OFFSET(25)] AS iqr
  FROM (
     SELECT group_label, APPROX_QUANTILES(vital_instability, 100) AS quantiles
     FROM hourly_vital_all
     GROUP BY group_label
  ) AS q
)

-- 13) Final join: emit one row per group with all requested metrics
SELECT gs.group_label,
       gs.mean_icu_los,
       gs.mortality_rate,
       gs.mean_hypotensive_hours,
       gs.mean_tachy_hours,
       gs.mean_concurrent_hours,
       vp.p25,
       vp.p50,
       vp.p75,
       vp.p90,
       vp.iqr
FROM group_stats gs
JOIN vital_percentiles vp
  ON gs.group_label = vp.group_label
ORDER BY gs.group_label;