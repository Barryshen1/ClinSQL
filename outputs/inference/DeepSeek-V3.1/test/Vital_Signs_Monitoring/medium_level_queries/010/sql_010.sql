WITH eligible_stays AS (
  SELECT 
    ie.stay_id,
    ie.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
),
sbp_measurements AS (
  SELECT 
    es.stay_id,
    ce.valuenum AS sbp
  FROM eligible_stays es
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON es.stay_id = ce.stay_id
  WHERE ce.itemid IN (220179, 220050, 225309)  -- SBP itemids
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0  -- exclude negative values
    AND ce.charttime >= es.intime
    AND ce.charttime <= DATETIME_ADD(es.intime, INTERVAL 48 HOUR)
),
avg_sbp_per_stay AS (
  SELECT 
    stay_id,
    AVG(sbp) AS avg_sbp
  FROM sbp_measurements
  GROUP BY stay_id
  HAVING avg_sbp IS NOT NULL
)
SELECT
  COUNTIF(avg_sbp <= 160) / COUNT(*) AS percentile_160
FROM avg_sbp_per_stay;