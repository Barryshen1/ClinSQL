WITH cohort AS (
  SELECT 
    icu.stay_id,
    p.anchor_age,
    p.anchor_year,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM icu.intime) - p.anchor_year) BETWEEN 80 AND 90
),
heart_rate_avg AS (
  SELECT 
    c.stay_id,
    AVG(ce.valuenum) AS avg_hr
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.itemid = 220045  -- Standard heart rate itemid
    AND ce.valuenum IS NOT NULL
  GROUP BY c.stay_id
)
SELECT 
  (COUNTIF(avg_hr <= 110) * 100.0) / COUNT(*) AS percentile
FROM heart_rate_avg;