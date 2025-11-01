WITH cohort AS (
  SELECT 
    s.stay_id,
    p.anchor_age + (EXTRACT(YEAR FROM s.intime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
cohort_with_age AS (
  SELECT 
    stay_id
  FROM cohort
  WHERE age BETWEEN 85 AND 95
),
temperature_averages AS (
  SELECT
    c.stay_id,
    AVG(ce.valuenum) AS avg_temp
  FROM cohort_with_age c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.itemid = 223762  -- Temperature Celsius
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 30 AND 45  -- Valid physiological range
  GROUP BY c.stay_id
)
SELECT
  SAFE_DIVIDE(
    (SUM(CASE WHEN avg_temp < 36.0 THEN 1 ELSE 0 END) 
     + 0.5 * SUM(CASE WHEN avg_temp = 36.0 THEN 1 ELSE 0 END)),
    COUNT(*)
  ) * 100 AS percentile_rank
FROM temperature_averages;