WITH digoxin_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE LOWER(p.drug) LIKE '%digoxin%'
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
),
cohort_raw AS (
  SELECT
    dp.subject_id,
    dp.hadm_id,
    TIMESTAMP_DIFF(dp.stoptime, dp.starttime, SECOND) / 86400.0 AS duration_days
  FROM digoxin_prescriptions dp
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON dp.subject_id = a.subject_id
   AND dp.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON a.subject_id = pat.subject_id
  WHERE
    pat.gender IS NOT NULL
    AND LOWER(pat.gender) IN ('m','male')
    AND pat.anchor_age IS NOT NULL
    AND pat.anchor_year IS NOT NULL
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- age at admission estimation
    AND (pat.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pat.anchor_year)) BETWEEN 86 AND 96
),
cohort AS (
  SELECT *
  FROM cohort_raw
  WHERE duration_days > 0
),
stats AS (
  SELECT
    APPROX_QUANTILES(duration_days, 100) AS quantiles,
    COUNT(*) AS n_prescriptions
  FROM cohort
)
SELECT
  quantiles[OFFSET(25)] AS q1_25th_percentile_days,
  quantiles[OFFSET(75)] AS q3_75th_percentile_days,
  quantiles[OFFSET(75)] - quantiles[OFFSET(25)] AS iqr_days,
  n_prescriptions
FROM stats;