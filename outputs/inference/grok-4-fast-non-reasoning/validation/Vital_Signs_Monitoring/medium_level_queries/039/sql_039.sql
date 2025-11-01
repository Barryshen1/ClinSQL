WITH first_stays AS (
  SELECT *
  FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  )
  WHERE rn = 1
),
patients AS (
  SELECT subject_id, gender, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
),
map_measurements AS (
  SELECT ce.subject_id, ce.hadm_id, ce.stay_id, ce.charttime, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN first_stays fs ON ce.stay_id = fs.stay_id
  INNER JOIN patients p ON ce.subject_id = p.subject_id
  WHERE ce.itemid = 220052
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND fs.los >= 2
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.charttime >= fs.intime
    AND ce.charttime <= fs.intime + INTERVAL 2 DAY
),
qualifying_stays AS (
  SELECT 
    stay_id,
    COUNT(DISTINCT charttime) AS num_measurements,
    AVG(valuenum) AS avg_map
  FROM map_measurements
  GROUP BY stay_id
  HAVING num_measurements >= 3
)
SELECT 
  60 AS target_avg_map,
  PERCENT_RANK() OVER (ORDER BY avg_map) * 100 AS percentile
FROM qualifying_stays
WHERE avg_map = 60  -- For the specific patient's average; adjust if exact match not needed
ORDER BY percentile;