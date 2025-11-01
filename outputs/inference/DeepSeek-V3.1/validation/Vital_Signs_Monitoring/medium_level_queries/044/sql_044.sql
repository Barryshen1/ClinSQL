WITH patient_stays AS (
  SELECT 
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    DATETIME_ADD(ie.intime, INTERVAL 48 HOUR) AS end_time_48hr,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
),

sbp_measurements AS (
  SELECT 
    ps.stay_id,
    AVG(ce.valuenum) AS avg_sbp
  FROM patient_stays ps
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ps.stay_id = ce.stay_id
  WHERE ce.itemid = 220179  -- Systolic blood pressure
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 300  -- Reasonable range filter
    AND ce.charttime >= ps.intime
    AND ce.charttime < ps.end_time_48hr
  GROUP BY ps.stay_id
  HAVING COUNT(ce.valuenum) >= 1  -- At least one measurement
),

percentiles AS (
  SELECT 
    APPROX_QUANTILES(avg_sbp, 100) AS pct
  FROM sbp_measurements
)

SELECT 
  (SELECT pct[OFFSET(50)] FROM percentiles) AS median_sbp,
  (SELECT MIN(offset) 
   FROM percentiles, UNNEST(pct) AS percentile_value WITH OFFSET offset
   WHERE percentile_value >= 150
  ) AS percentile_rank
FROM percentiles
LIMIT 1;