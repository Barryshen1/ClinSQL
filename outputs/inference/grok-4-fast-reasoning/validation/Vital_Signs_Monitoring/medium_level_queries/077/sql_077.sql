WITH qualifying_stays AS (
  SELECT 
    icu.stay_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 42 AND 52
),
avg_hr_per_stay AS (
  SELECT 
    qs.stay_id,
    AVG(ce.valuenum) AS avg_hr
  FROM qualifying_stays AS qs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.stay_id = qs.stay_id
  WHERE ce.itemid = 220045 
    AND ce.valuenum IS NOT NULL
  GROUP BY qs.stay_id
)
SELECT 
  COUNT(*) AS cohort_size,
  ROUND((COUNTIF(avg_hr <= 90) * 100.0 / COUNT(*)), 2) AS percentile
FROM avg_hr_per_stay;