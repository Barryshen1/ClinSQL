WITH cohort AS (
  SELECT 
    i.stay_id,
    p.subject_id,
    p.anchor_age,
    i.intime,
    i.outtime,
    i.los,
    p.gender,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
),

chart_events AS (
  SELECT 
    c.stay_id,
    c.itemid,
    c.valuenum,
    c.charttime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN cohort 
    ON c.stay_id = cohort.stay_id
  WHERE c.itemid IN (52, 211)  -- MAP (52), HR (211)
    AND c.charttime BETWEEN cohort.intime AND DATETIME_ADD(cohort.intime, INTERVAL 48 HOUR)
),

composite_scores AS (
  SELECT 
    c.stay_id,
    SUM(CASE WHEN ce.itemid = 52 AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS hypotension_count,
    SUM(CASE WHEN ce.itemid = 211 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_count,
    (SUM(CASE WHEN ce.itemid = 52 AND ce.valuenum < 65 THEN 1 ELSE 0 END) +
     SUM(CASE WHEN ce.itemid = 211 AND ce.valuenum > 100 THEN 1 ELSE 0 END)) AS composite_score
  FROM cohort c
  LEFT JOIN chart_events ce 
    ON c.stay_id = ce.stay_id
  GROUP BY c.stay_id
),

percentiles AS (
  SELECT 
    PERCENTILE_CONT(composite_score, 0.95) WITHIN GROUP (ORDER BY composite_score) AS p95,
    PERCENTILE_CONT(composite_score, 0.75) WITHIN GROUP (ORDER BY composite_score) AS p75
  FROM composite_scores
),

top_quartile AS (
  SELECT 
    cs.stay_id,
    cs.composite_score,
    c.los,
    c.hospital_expire_flag,
    cs.hypotension_count,
    cs.tachycardia_count
  FROM composite_scores cs
  JOIN cohort c 
    ON cs.stay_id = c.stay_id
  CROSS JOIN percentiles p
  WHERE cs.composite_score >= p.p75
),

entire_cohort AS (
  SELECT 
    cs.stay_id,
    cs.composite_score,
    c.los,
    c.hospital_expire_flag,
    cs.hypotension_count,
    cs.tachycardia_count
  FROM composite_scores cs
  JOIN cohort c 
    ON cs.stay_id = c.stay_id
)

SELECT 
  p.p95 AS '95th_percentile_composite_score',
  'top_quartile' AS group_type,
  AVG(CASE WHEN t.hypotension_count > 0 THEN 1 ELSE 0 END) AS hypotension_rate,
  AVG(CASE WHEN t.tachycardia_count > 0 THEN 1 ELSE 0 END) AS tachycardia_rate,
  AVG(t.los) AS avg_los,
  AVG(CAST(t.hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM top_quartile t
CROSS JOIN percentiles p

UNION ALL

SELECT 
  p.p95,
  'entire_cohort',
  AVG(CASE WHEN e.hypotension_count > 0 THEN 1 ELSE 0 END),
  AVG(CASE WHEN e.tachycardia_count > 0 THEN 1 ELSE 0 END),
  AVG(e.los),
  AVG(CAST(e.hospital_expire_flag AS FLOAT64))
FROM entire_cohort e
CROSS JOIN percentiles p;