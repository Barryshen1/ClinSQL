WITH rrt_patients AS (
  SELECT DISTINCT i.stay_id, i.subject_id, i.hadm_id, i.intime, i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON i.stay_id = pe.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE p.anchor_age BETWEEN 70 AND 80
    AND p.gender = 'M'
    AND (
      LOWER(di.label) LIKE '%dialysis%'
      OR LOWER(di.label) LIKE '%crrt%'
      OR LOWER(di.label) LIKE '%hemodialysis%'
      OR LOWER(di.label) LIKE '%rrt%'
    )
),

composite_score AS (
  SELECT 
    i.stay_id,
    SUM(CASE 
      WHEN ce.itemid IN (
        SELECT itemid 
        FROM `physionet-data.mimiciv_3_1_icu.d_items` 
        WHERE LOWER(label) IN ('map', 'mean arterial pressure')
      ) 
      AND ce.valuenum < 65 
      AND ce.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
      THEN 1 ELSE 0 END) AS hypotension_events,
    SUM(CASE 
      WHEN ce.itemid IN (
        SELECT itemid 
        FROM `physionet-data.mimiciv_3_1_icu.d_items` 
        WHERE LOWER(label) IN ('heart rate', 'hr', 'pulse')
      ) 
      AND ce.valuenum > 100 
      AND ce.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
      THEN 1 ELSE 0 END) AS tachycardia_events,
    (SUM(CASE 
      WHEN ce.itemid IN (
        SELECT itemid 
        FROM `physionet-data.mimiciv_3_1_icu.d_items` 
        WHERE LOWER(label) IN ('map', 'mean arterial pressure')
      ) 
      AND ce.valuenum < 65 
      AND ce.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
      THEN 1 ELSE 0 END) +
     SUM(CASE 
      WHEN ce.itemid IN (
        SELECT itemid 
        FROM `physionet-data.mimiciv_3_1_icu.d_items` 
        WHERE LOWER(label) IN ('heart rate', 'hr', 'pulse')
      ) 
      AND ce.valuenum > 100 
      AND ce.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
      THEN 1 ELSE 0 END)) AS composite_score
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON i.stay_id = ce.stay_id
  WHERE p.anchor_age BETWEEN 70 AND 80
    AND p.gender = 'M'
  GROUP BY i.stay_id
),

percentile_90 AS (
  SELECT PERCENTILE_CONT(composite_score, 0.9) OVER () AS p90_score
  FROM composite_score cs
  INNER JOIN rrt_patients r ON cs.stay_id = r.stay_id
  LIMIT 1
),

top_decile_rrt AS (
  SELECT cs.stay_id, cs.composite_score, cs.hypotension_events, cs.tachycardia_events, r.los, a.hospital_expire_flag
  FROM composite_score cs
  INNER JOIN rrt_patients r ON cs.stay_id = r.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON r.hadm_id = a.hadm_id
  CROSS JOIN percentile_90 p
  WHERE cs.composite_score >= p.p90_score
),

non_rrt AS (
  SELECT 
    cs.hypotension_events,
    cs.tachycardia_events,
    i.los,
    a.hospital_expire_flag
  FROM composite_score cs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON cs.stay_id = i.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  LEFT JOIN rrt_patients r ON i.stay_id = r.stay_id
  WHERE p.anchor_age BETWEEN 70 AND 80
    AND p.gender = 'M'
    AND r.stay_id IS NULL
)

SELECT
  'Top Decile RRT' AS group_name,
  AVG(hypotension_events) AS avg_hypotension_events,
  AVG(tachycardia_events) AS avg_tachycardia_events,
  AVG(los) AS avg_icu_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM top_decile_rrt

UNION ALL

SELECT
  'Non-RRT' AS group_name,
  AVG(hypotension_events) AS avg_hypotension_events,
  AVG(tachycardia_events) AS avg_tachycardia_events,
  AVG(los) AS avg_icu_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM non_rrt;