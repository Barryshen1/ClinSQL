WITH cohort_stays AS (
  SELECT 
    icu.stay_id,
    icu.intime,
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    -- Age filter: 83 to 93 years
    AND (p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year)) BETWEEN 83 AND 93
),

map_events AS (
  SELECT 
    ce.stay_id,
    ce.valuenum AS map_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohort_stays cs
    ON ce.stay_id = cs.stay_id
  WHERE 
    ce.itemid IN (220052, 456)  -- MAP item_ids
    AND ce.valuenum IS NOT NULL  -- Ensure numeric values
    -- First 48 hours of ICU stay
    AND ce.charttime >= cs.intime
    AND ce.charttime <= DATETIME_ADD(cs.intime, INTERVAL 48 HOUR)
),

stay_avg_map AS (
  SELECT 
    stay_id,
    AVG(map_value) AS avg_map,
    COUNT(*) AS num_measurements
  FROM map_events
  GROUP BY stay_id
  HAVING COUNT(*) >= 3  -- Minimum 3 measurements
)

-- Calculate percentile for 60 mmHg
SELECT 
  (COUNTIF(avg_map <= 60) * 100.0) / COUNT(*) AS percentile
FROM stay_avg_map;