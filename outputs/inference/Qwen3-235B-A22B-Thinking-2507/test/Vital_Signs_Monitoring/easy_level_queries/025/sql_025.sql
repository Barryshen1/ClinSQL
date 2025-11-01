WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' 
    AND anchor_age BETWEEN 39 AND 49
),
icu_stays AS (
  SELECT stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN filtered_patients p
    ON icu.subject_id = p.subject_id
),
respiratory_rates AS (
  SELECT 
    stay_id,
    valuenum AS rr_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE stay_id IN (SELECT stay_id FROM icu_stays)
    AND itemid = 220210  -- Standard respiratory rate itemid
    AND valuenum IS NOT NULL
    AND valuenum > 0     -- Exclude invalid measurements
),
mean_rr_per_stay AS (
  SELECT 
    stay_id,
    AVG(rr_value) AS mean_rr
  FROM respiratory_rates
  GROUP BY stay_id
  HAVING COUNT(*) > 0   -- Ensure at least one valid measurement
)
SELECT 
  APPROX_QUANTILES(mean_rr, 10000)[OFFSET(7500)] AS percentile_75
FROM mean_rr_per_stay;