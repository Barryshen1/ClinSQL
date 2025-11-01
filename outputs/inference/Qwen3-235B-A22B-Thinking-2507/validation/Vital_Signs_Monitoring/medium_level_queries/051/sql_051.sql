WITH qualifying_stays AS (
  SELECT 
    i.subject_id,
    i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) BETWEEN 55 AND 65
),
heart_rate AS (
  SELECT 
    c.subject_id,
    c.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN qualifying_stays qs
    ON c.stay_id = qs.stay_id
  WHERE c.itemid = 220045
    AND c.valuenum IS NOT NULL
),
max_hr_per_patient AS (
  SELECT 
    subject_id,
    MAX(valuenum) AS max_hr
  FROM heart_rate
  GROUP BY subject_id
)
SELECT 
  APPROX_QUANTILES(max_hr, 1000)[OFFSET(750)] - APPROX_QUANTILES(max_hr, 1000)[OFFSET(250)] AS iqr
FROM max_hr_per_patient;