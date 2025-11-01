WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.anchor_year,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 84 AND 94
),
aspirin AS (
  SELECT 
    p.hadm_id,
    GREATEST(p.starttime, c.admittime) AS starttime,
    LEAST(COALESCE(p.stoptime, '9999-01-01'), c.dischtime) AS stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN cohort c
    ON p.hadm_id = c.hadm_id
  WHERE (LOWER(p.drug) LIKE '%aspirin%' OR LOWER(p.drug) LIKE '%acetylsalicylic acid%')
    AND GREATEST(p.starttime, c.admittime) < LEAST(COALESCE(p.stoptime, '9999-01-01'), c.dischtime)
),
p2y12 AS (
  SELECT 
    p.hadm_id,
    GREATEST(p.starttime, c.admittime) AS starttime,
    LEAST(COALESCE(p.stoptime, '9999-01-01'), c.dischtime) AS stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN cohort c
    ON p.hadm_id = c.hadm_id
  WHERE (LOWER(p.drug) LIKE '%clopidogrel%' 
         OR LOWER(p.drug) LIKE '%prasugrel%' 
         OR LOWER(p.drug) LIKE '%ticagrelor%')
    AND GREATEST(p.starttime, c.admittime) < LEAST(COALESCE(p.stoptime, '9999-01-01'), c.dischtime)
),
events AS (
  SELECT 
    hadm_id,
    starttime AS time,
    1 AS aspirin_delta,
    0 AS p2y12_delta
  FROM aspirin
  UNION ALL
  SELECT 
    hadm_id,
    stoptime,
    -1,
    0
  FROM aspirin
  UNION ALL
  SELECT 
    hadm_id,
    starttime,
    0,
    1
  FROM p2y12
  UNION ALL
  SELECT 
    hadm_id,
    stoptime,
    0,
    -1
  FROM p2y12
),
events_with_running AS (
  SELECT 
    hadm_id,
    time,
    SUM(aspirin_delta) OVER (PARTITION BY hadm_id ORDER BY time, aspirin_delta DESC, p2y12_delta DESC) AS aspirin_count,
    SUM(p2y12_delta) OVER (PARTITION BY hadm_id ORDER BY time, aspirin_delta DESC, p2y12_delta DESC) AS p2y12_count
  FROM events
),
segments AS (
  SELECT 
    hadm_id,
    time AS start_time,
    LEAD(time) OVER (PARTITION BY hadm_id ORDER BY time) AS end_time,
    aspirin_count > 0 AS aspirin_active,
    p2y12_count > 0 AS p2y12_active
  FROM events_with_running
),
dapt_segments AS (
  SELECT 
    hadm_id,
    start_time,
    end_time,
    TIMESTAMP_DIFF(end_time, start_time, SECOND) AS duration_seconds
  FROM segments
  WHERE aspirin_active AND p2y12_active
    AND end_time IS NOT NULL
),
dapt_duration AS (
  SELECT 
    hadm_id,
    SUM(duration_seconds) AS total_dapt_seconds
  FROM dapt_segments
  GROUP BY hadm_id
)
SELECT 
  MAX(total_dapt_seconds) / (24*60*60) AS max_dapt_duration_days
FROM dapt_duration;