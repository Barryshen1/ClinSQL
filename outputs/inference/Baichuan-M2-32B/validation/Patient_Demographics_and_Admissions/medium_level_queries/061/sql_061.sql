WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    a.insurance,
    a.admission_type,
    (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND a.insurance = 'Medicare'
    AND a.admission_type = 'URGENT'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND p.anchor_year IS NOT NULL
    AND p.anchor_age IS NOT NULL
),
filtered_cohort AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'home'
      WHEN discharge_location IN ('SNF', 'HOSPICE', 'REHAB', 'LONG TERM CARE FACILITY', 'SKILLED NURSING FACILITY') THEN 'facility'
      ELSE 'other'
    END AS discharge_outcome
  FROM cohort
  WHERE age_at_admission BETWEEN 86 AND 96
),
los_data AS (
  SELECT
    hadm_id,
    discharge_outcome,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los
  FROM filtered_cohort
  WHERE discharge_outcome IN ('home', 'facility', 'in-hospital death')
),
outcome_stats AS (
  SELECT
    discharge_outcome,
    AVG(los) AS mean_los,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
    APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
    APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los
  FROM los_data
  GROUP BY discharge_outcome
),
percentile_10day AS (
  SELECT
    (SELECT COUNT(*) FROM los_data WHERE los <= 10) * 100.0 / COUNT(*) AS percentile_10day
  FROM los_data
)
SELECT
  os.*,
  p.percentile_10day
FROM outcome_stats os
CROSS JOIN percentile_10day p;