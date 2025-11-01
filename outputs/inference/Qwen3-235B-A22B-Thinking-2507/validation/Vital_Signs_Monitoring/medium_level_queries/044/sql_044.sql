WITH population_stays AS (
  SELECT 
    ie.stay_id,
    ie.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) BETWEEN 81 AND 91
),
sbp_measurements AS (
  SELECT 
    ps.stay_id,
    ce.valuenum
  FROM population_stays ps
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ps.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (220050, 220179, 225309)  -- Systolic BP item IDs
    AND ce.charttime >= ps.intime
    AND ce.charttime <= TIMESTAMP_ADD(ps.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
),
stay_avg AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS avg_sbp
  FROM sbp_measurements
  GROUP BY stay_id
)
SELECT 
  COUNTIF(avg_sbp <= 150) * 100.0 / COUNT(*) AS percentile_rank
FROM stay_avg;