WITH bp_data AS (
  SELECT 
    ie.stay_id,
    AVG(ce.valuenum) AS avg_sbp_first_24h
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON ie.stay_id = ce.stay_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
    AND ce.itemid IN (220179, 220050)  -- Systolic BP items
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0  -- Exclude erroneous values
    AND ce.charttime >= ie.intime
    AND ce.charttime < DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
  GROUP BY ie.stay_id
  HAVING COUNT(ce.valuenum) > 0  -- Ensure at least one measurement
)
SELECT 
  PERCENT_RANK() OVER (ORDER BY avg_sbp_first_24h) * 100 AS percentile_rank
FROM bp_data
WHERE avg_sbp_first_24h = 150;