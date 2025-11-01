WITH cohort AS (
  SELECT 
    stays.stay_id,
    stays.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` stays
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON stays.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM stays.intime) - pat.anchor_year)) BETWEEN 45 AND 55
),
instability_events AS (
  SELECT 
    ce.stay_id,
    SUM(CASE WHEN ce.itemid IN (220179, 220052) AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS hypotension_count,
    SUM(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohort c
    ON ce.stay_id = c.stay_id
  WHERE 
    ce.itemid IN (220179, 220052, 220045)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY ce.stay_id
),
instability_scores AS (
  SELECT 
    c.stay_id,
    COALESCE(ie.hypotension_count, 0) + COALESCE(ie.tachycardia_count, 0) AS instability_score
  FROM cohort c
  LEFT JOIN instability_events ie
    ON c.stay_id = ie.stay_id
)
SELECT 
  PERCENTILE_CONT(instability_score, 0.95) OVER () AS p95_instability_score
FROM instability_scores
LIMIT 1;