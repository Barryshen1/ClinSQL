WITH cohort AS (
  SELECT 
    ie.stay_id,
    ie.intime,
    ie.outtime,
    -- Approximate age at ICU admission
    pt.anchor_age + (EXTRACT(YEAR FROM ie.intime) - pt.anchor_year) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON ie.subject_id = pt.subject_id
  WHERE pt.gender = 'F'
),
filtered_cohort AS (
  SELECT stay_id, intime, outtime
  FROM cohort
  WHERE age_at_icu BETWEEN 42 AND 52
),
hr_data AS (
  SELECT 
    fc.stay_id,
    ce.valuenum AS hr_value
  FROM filtered_cohort fc  -- Fixed typo: 'filted_cohort' -> 'filtered_cohort'
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fc.stay_id = ce.stay_id
    AND ce.itemid IN (211, 220045)  -- Heart Rate item_ids
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= fc.intime
    AND ce.charttime <= fc.outtime
),
avg_hr_per_stay AS (
  SELECT 
    stay_id,
    AVG(hr_value) AS avg_hr
  FROM hr_data
  GROUP BY stay_id
)
SELECT
  COUNT(*) AS cohort_size,
  ROUND(
    (SUM(CASE WHEN avg_hr <= 90 THEN 1 ELSE 0 END) * 100.0) / COUNT(*),
    2
  ) AS percentile
FROM avg_hr_per_stay;