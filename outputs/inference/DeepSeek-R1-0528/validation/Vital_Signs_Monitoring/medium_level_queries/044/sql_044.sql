WITH cohort AS (
  SELECT 
    ie.stay_id,
    ie.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON ie.subject_id = pt.subject_id
  WHERE 
    pt.gender = 'M' 
    AND pt.anchor_age BETWEEN 81 AND 91
),
sbp_data AS (
  SELECT 
    c.stay_id,
    ce.valuenum AS sbp
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (220179, 225309)  -- Systolic BP item IDs
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
),
per_stay_avg AS (
  SELECT 
    stay_id,
    AVG(sbp) AS avg_sbp
  FROM sbp_data
  GROUP BY stay_id
)
SELECT 
  (COUNTIF(avg_sbp <= 150) / COUNT(*)) * 100 AS percentile
FROM per_stay_avg;