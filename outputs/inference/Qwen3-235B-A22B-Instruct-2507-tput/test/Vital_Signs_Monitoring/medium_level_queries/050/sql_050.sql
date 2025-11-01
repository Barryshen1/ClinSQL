WITH patient_stays AS (
  SELECT 
    s.stay_id,
    s.subject_id,
    s.intime,
    p.gender,
    (EXTRACT(YEAR FROM s.intime) - p.anchor_year + p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM s.intime) - p.anchor_year + p.anchor_age) BETWEEN 67 AND 77
),
hr_measurements AS (
  SELECT 
    ps.stay_id,
    ce.valuenum AS heart_rate
  FROM patient_stays ps
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ps.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE di.label = 'Heart Rate'
    AND ce.charttime >= ps.intime
    AND ce.charttime < DATETIME_ADD(ps.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
),
avg_hr_per_stay AS (
  SELECT 
    stay_id,
    AVG(heart_rate) AS avg_hr
  FROM hr_measurements
  GROUP BY stay_id
),
cohort_stats AS (
  SELECT 
    COUNT(*) AS total_stays,
    SUM(CASE WHEN avg_hr <= 110 THEN 1 ELSE 0 END) AS stays_at_or_below_110
  FROM avg_hr_per_stay
)
SELECT 
  (stays_at_or_below_110 * 100.0 / total_stays) AS percentile_rank
FROM cohort_stats;