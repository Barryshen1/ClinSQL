WITH cohort_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    a.admittime,
    a.dischtime,
    GREATEST(pr.starttime, a.admittime) AS start_eff,
    LEAST(COALESCE(pr.stoptime, a.dischtime), a.dischtime) AS end_eff
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pr.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pr.hadm_id = a.hadm_id
       AND pr.subject_id = a.subject_id
  WHERE LOWER(COALESCE(pr.drug, '')) LIKE '%digoxin%'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    AND pr.starttime IS NOT NULL
),

durations AS (
  -- duration in days (fractional), censored to within the hospital admission
  SELECT
    SAFE_DIVIDE(TIMESTAMP_DIFF(end_eff, start_eff, SECOND), 86400) AS duration_days
  FROM cohort_prescriptions
  WHERE end_eff > start_eff
)

SELECT
  (SELECT COUNT(*) FROM durations) AS n_prescriptions_included,
  quantiles[OFFSET(25)] AS p25_days,
  quantiles[OFFSET(75)] AS p75_days,
  quantiles[OFFSET(75)] - quantiles[OFFSET(25)] AS iqr_days
FROM (
  SELECT APPROX_QUANTILES(duration_days, 100) AS quantiles
  FROM durations
);