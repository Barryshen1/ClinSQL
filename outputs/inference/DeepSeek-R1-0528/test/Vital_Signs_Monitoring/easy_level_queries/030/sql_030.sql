WITH cohort AS (
  SELECT 
    ie.stay_id,
    p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
filtered_cohort AS (
  SELECT stay_id
  FROM cohort
  WHERE age_at_icu BETWEEN 38 AND 48
),
first_hr_time AS (
  SELECT 
    ce.stay_id,
    MIN(ce.charttime) AS first_charttime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN filtered_cohort fc 
    ON ce.stay_id = fc.stay_id
  WHERE ce.itemid = 220045  -- Heart Rate itemid
  GROUP BY ce.stay_id
),
first_hr_value AS (
  SELECT 
    ce.stay_id,
    MIN(ce.valuenum) AS first_hr  -- Min value at first measurement time
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN first_hr_time fht 
    ON ce.stay_id = fht.stay_id 
    AND ce.charttime = fht.first_charttime
  WHERE ce.itemid = 220045
  GROUP BY ce.stay_id
)
SELECT 
  MIN(first_hr) AS min_first_heart_rate
FROM first_hr_value;