WITH cohort AS (
  SELECT 
    ie.subject_id,
    ie.stay_id,
    ie.intime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
filtered_cohort AS (
  SELECT *
  FROM cohort
  WHERE age_at_admission BETWEEN 51 AND 61
),
rr_events AS (
  SELECT 
    fc.stay_id,
    ce.charttime,
    ce.valuenum AS rr_value
  FROM filtered_cohort fc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fc.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (220210, 224688, 224689, 224690)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= fc.intime
    AND ce.charttime <= DATETIME_ADD(fc.intime, INTERVAL 1 HOUR)
),
first_rr_time AS (
  SELECT 
    stay_id,
    MIN(charttime) AS first_charttime
  FROM rr_events
  GROUP BY stay_id
),
first_rr_values AS (
  SELECT 
    f.stay_id,
    AVG(r.rr_value) AS first_rr  -- Average if multiple measurements at first time
  FROM first_rr_time f
  INNER JOIN rr_events r
    ON f.stay_id = r.stay_id AND f.first_charttime = r.charttime
  GROUP BY f.stay_id
)
SELECT 
  APPROX_QUANTILES(first_rr, 100)[OFFSET(25)] AS percentile_25
FROM first_rr_values;