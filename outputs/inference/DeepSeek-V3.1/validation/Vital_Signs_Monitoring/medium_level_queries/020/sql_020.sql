WITH cohort AS (
  SELECT 
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id,
    ie.intime,
    ie.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
), map_48hr AS (
  SELECT 
    c.stay_id,
    AVG(ce.valuenum) AS mean_map
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.itemid IN (220181, 225312)  -- Invasive and non-invasive MAP
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.stay_id
), percentiles AS (
  SELECT
    stay_id,
    mean_map,
    PERCENT_RANK() OVER (ORDER BY mean_map) AS percentile_rank
  FROM map_48hr
)
SELECT 
  percentile_rank * 100 AS percentile
FROM percentiles
WHERE mean_map = 85
LIMIT 1;