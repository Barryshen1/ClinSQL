WITH cohort AS (
  SELECT
    ie.stay_id,
    ie.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
), 
sbp_data AS (
  SELECT
    c.stay_id,
    ce.valuenum AS sbp
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE
    ce.itemid IN (220050, 220179)  -- Systolic BP item IDs
    AND ce.valuenum IS NOT NULL    -- Ensure numeric value
    AND ce.charttime >= c.intime
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
),
avg_sbp_per_stay AS (
  SELECT
    stay_id,
    AVG(sbp) AS avg_sbp
  FROM sbp_data
  GROUP BY stay_id
  HAVING AVG(sbp) IS NOT NULL  -- Exclude stays with no measurements
)
SELECT
  ( 
    COUNTIF(avg_sbp <= 160) * 100.0 / 
    COUNT(*) 
  ) AS percentile_160
FROM avg_sbp_per_stay;