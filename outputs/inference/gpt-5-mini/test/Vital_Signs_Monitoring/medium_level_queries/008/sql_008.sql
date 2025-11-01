WITH stays AS (
  -- ICU stays for male patients aged 39-49
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
),

map_events AS (
  -- Explicit MAP measurements in the first 24 hours of each ICU stay
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.valuenum,
    d.label
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  JOIN stays s
    ON c.subject_id = s.subject_id
   AND c.hadm_id = s.hadm_id
   AND c.stay_id = s.stay_id
  WHERE c.valuenum IS NOT NULL
    -- first 24 hours from ICU intime
    AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
    -- match item labels likely representing mean arterial pressure
    AND REGEXP_CONTAINS(LOWER(d.label), r'mean\s*(arterial|bp|blood pressure)|\bmap\b')
),

per_stay_map AS (
  -- per-stay average MAP over first 24 hours
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    AVG(valuenum) AS avg_map
  FROM map_events
  GROUP BY stay_id, subject_id, hadm_id
),

stats AS (
  SELECT
    COUNT(*) AS total_stays,
    SUM(CASE WHEN avg_map <= 75 THEN 1 ELSE 0 END) AS num_le_75,
    SUM(CASE WHEN avg_map = 75 THEN 1 ELSE 0 END) AS num_eq_75
  FROM per_stay_map
)

SELECT
  total_stays,
  num_le_75,
  num_eq_75,
  -- percentile: percent of per-stay average MAP values <= 75 mmHg
  ROUND(100.0 * SAFE_DIVIDE(num_le_75, total_stays), 2) AS percentile_of_75
FROM stats;