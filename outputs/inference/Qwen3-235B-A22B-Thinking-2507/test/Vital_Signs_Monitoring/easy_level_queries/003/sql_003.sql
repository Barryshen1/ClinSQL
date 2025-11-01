WITH filtered_stays AS (
  SELECT 
    s.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM s.intime) - p.anchor_year)) BETWEEN 40 AND 50
),
stay_heart_rates AS (
  SELECT 
    fs.stay_id,
    ce.valuenum AS heart_rate
  FROM filtered_stays fs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fs.stay_id = ce.stay_id
  WHERE ce.itemid = 220045  -- Standard heart rate itemid
    AND ce.valuenum IS NOT NULL
),
per_stay_mean AS (
  SELECT 
    stay_id,
    AVG(heart_rate) AS mean_hr
  FROM stay_heart_rates
  GROUP BY stay_id
)
SELECT 
  APPROX_QUANTILES(mean_hr, 2)[OFFSET(1)] AS median_mean_hr
FROM per_stay_mean;