WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    -- Calculate true age at admission (adjust for >89 shift)
    (CASE WHEN p.anchor_age <= 89 THEN p.anchor_age ELSE 300 - p.anchor_age END) 
      + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
),
filtered_cohort AS (
  SELECT *
  FROM cohort
  WHERE age_at_admission BETWEEN 84 AND 94
),
antiplatelet_prescriptions AS (
  SELECT 
    pr.subject_id, 
    pr.hadm_id, 
    pr.starttime, 
    LEAST(COALESCE(pr.stoptime, c.dischtime), c.dischtime) AS stoptime,
    pr.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN filtered_cohort c
    ON pr.subject_id = c.subject_id AND pr.hadm_id = c.hadm_id
  WHERE 
    (LOWER(pr.drug) LIKE '%aspirin%'
      OR LOWER(pr.drug) LIKE '%clopidogrel%'
      OR LOWER(pr.drug) LIKE '%prasugrel%'
      OR LOWER(pr.drug) LIKE '%ticagrelor%'
      OR LOWER(pr.drug) LIKE '%dipyridamole%'
      OR LOWER(pr.drug) LIKE '%ticlopidine%'
      OR LOWER(pr.drug) LIKE '%plavix%'
      OR LOWER(pr.drug) LIKE '%effient%'
      OR LOWER(pr.drug) LIKE '%brilinta%')
    AND pr.starttime <= COALESCE(pr.stoptime, c.dischtime)
),
events AS (
  SELECT 
    hadm_id,
    starttime AS event_time,
    1 AS event
  FROM antiplatelet_prescriptions
  UNION ALL
  SELECT 
    hadm_id,
    stoptime AS event_time,
    -1 AS event
  FROM antiplatelet_prescriptions
),
event_series AS (
  SELECT 
    hadm_id,
    event_time,
    event,
    SUM(event) OVER (PARTITION BY hadm_id ORDER BY event_time, event) AS active_count
  FROM events
),
period_edges AS (
  SELECT 
    hadm_id,
    event_time,
    active_count,
    LAG(active_count) OVER (PARTITION BY hadm_id ORDER BY event_time, event) AS prev_count
  FROM event_series
),
starts AS (
  SELECT 
    hadm_id,
    event_time AS start_time,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY event_time) AS rn
  FROM period_edges
  WHERE active_count >= 2 AND COALESCE(prev_count, 0) < 2
),
ends AS (
  SELECT 
    hadm_id,
    event_time AS end_time,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY event_time) AS rn
  FROM period_edges
  WHERE active_count < 2 AND COALESCE(prev_count, 0) >= 2
),
dapt_periods AS (
  SELECT
    s.hadm_id,
    s.start_time,
    e.end_time,
    DATETIME_DIFF(e.end_time, s.start_time, HOUR) AS duration_hours
  FROM starts s
  INNER JOIN ends e
    ON s.hadm_id = e.hadm_id AND s.rn = e.rn
)
SELECT 
  MAX(duration_hours) / 24.0 AS max_duration_days
FROM dapt_periods;